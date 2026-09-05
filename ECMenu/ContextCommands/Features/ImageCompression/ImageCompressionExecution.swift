import Foundation

/// 一张输入图片及其预定输出时间。
nonisolated struct ImageCompressionItemPlan: Equatable, Sendable {
    let sourceURL: URL
    let outputDate: Date
}

/// 已冻结设置、处理顺序和文件时间的批量计划。
nonisolated struct ImageCompressionPlan: Equatable, Sendable {
    let settings: ImageCompressionSettings
    let items: [ImageCompressionItemPlan]

    static func make(
        imageURLs: [URL],
        settings: ImageCompressionSettings,
        baseDate: Date
    ) -> ImageCompressionPlan {
        let sortedURLs = imageURLs.sorted { lhs, rhs in
            let nameOrder = lhs.lastPathComponent.localizedStandardCompare(
                rhs.lastPathComponent
            )
            if nameOrder == .orderedSame {
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
            return nameOrder == .orderedAscending
        }
        return ImageCompressionPlan(
            settings: settings,
            items: sortedURLs.enumerated().map { index, sourceURL in
                ImageCompressionItemPlan(
                    sourceURL: sourceURL,
                    outputDate: baseDate.addingTimeInterval(TimeInterval(index))
                )
            }
        )
    }
}

/// 在项目边界处理取消，逐项转换并排他写入，保留全部已生成输出。
nonisolated enum ImageCompressionExecution {
    static func execute(
        _ plan: ImageCompressionPlan,
        progress: ContextCommandProgressReporter? = nil
    ) async -> ImageCompressionReport {
        var items: [ImageCompressionItemResult] = []
        var wasCancelled = false

        for item in plan.items {
            if let progress, await progress.isCancellationRequested {
                wasCancelled = true
                break
            }
            guard !Task.isCancelled else { break }

            items.append(autoreleasepool {
                execute(item, settings: plan.settings)
            })
            if let progress {
                await progress.advance()
            }
        }

        return ImageCompressionReport(items: items, wasCancelled: wasCancelled)
    }

    private static func execute(
        _ item: ImageCompressionItemPlan,
        settings: ImageCompressionSettings
    ) -> ImageCompressionItemResult {
        let jpegData: Data
        do {
            jpegData = try ImageCompressionTranscoder.encodedJPEG(
                from: item.sourceURL,
                settings: settings
            )
        } catch {
            return .failed(.source(
                sourceURL: item.sourceURL,
                stage: (error as? ImageCompressionProcessingError)?.stage ?? .decode,
                error: SystemErrorSnapshot(capturing: error)
            ))
        }

        let outputURL: URL
        do {
            outputURL = try writeJPEGWithoutOverwriting(jpegData, for: item.sourceURL)
        } catch {
            return .failed(.destination(
                sourceURL: item.sourceURL,
                directoryURL: item.sourceURL.deletingLastPathComponent(),
                error: SystemErrorSnapshot(capturing: error)
            ))
        }

        let fileDateError: SystemErrorSnapshot?
        do {
            try FileManager.default.setAttributes(
                [.creationDate: item.outputDate, .modificationDate: item.outputDate],
                ofItemAtPath: outputURL.path
            )
            fileDateError = nil
        } catch {
            fileDateError = SystemErrorSnapshot(capturing: error)
        }
        return .output(ImageCompressionOutput(url: outputURL, fileDateError: fileDateError))
    }

    /// 编码结束后逐个排他尝试候选名，系统报告冲突时继续。
    private static func writeJPEGWithoutOverwriting(
        _ data: Data,
        for sourceURL: URL
    ) throws -> URL {
        let preferredURL = sourceURL.deletingPathExtension().appendingPathExtension("jpg")
        for candidateURL in FileCollisionNaming.candidateURLs(for: preferredURL) {
            do {
                try data.write(to: candidateURL, options: .withoutOverwriting)
                return candidateURL
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

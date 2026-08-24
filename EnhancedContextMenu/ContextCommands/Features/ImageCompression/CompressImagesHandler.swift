import AppKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

// MARK: - ==================== 类型化计划与结果 ====================

/// 描述一张源图片在批次中的确定顺序和输出文件时间。
nonisolated struct ImageCompressionItemPlan: Equatable, Sendable {
    /// 需要读取且始终保持不变的源文件 URL。
    let sourceURL: URL

    /// 成功输出后同时写入创建时间和修改时间的值。
    let outputDate: Date
}

/// 描述一整批图片压缩所需的不可变执行计划。
nonisolated struct ImageCompressionPlan: Equatable, Sendable {
    /// 用户确认的最大输出宽度。
    let maximumWidth: Int

    /// 已映射到 ImageIO 范围的 JPEG 压缩质量。
    let imageIOQuality: Double

    /// 按 Finder 风格文件名顺序排列的逐项计划。
    let items: [ImageCompressionItemPlan]
}

/// 一项图片处理失败时所处的系统阶段。
nonisolated enum ImageCompressionIssueStage: String, Equatable, Sendable {
    /// 无法读取或解码源图片。
    case decode

    /// 无法缩放或编码 JPG 数据。
    case encode

    /// 无法把编码结果写入源文件的同级目录。
    case write

    /// JPG 已生成，但无法设置要求的创建和修改时间。
    case fileDates

}

/// 图片批处理中一项没有完整完成的事实。
nonisolated struct ImageCompressionIssue: Equatable, Sendable {
    /// 发生失败的源文件或已经写出的目标文件。
    let itemURL: URL

    /// 失败发生的处理阶段。
    let stage: ImageCompressionIssueStage

    /// 决定用户反馈策略的稳定错误类别。
    let kind: FileSystemErrorKind

    /// 用于日志和稳定分类的底层错误快照。
    let systemError: SystemErrorSnapshot
}

/// 一批图片压缩完成后的成功输出和全部问题。
nonisolated struct ImageCompressionReport: Equatable, Sendable {
    /// 已经成功写入且需要由 Finder 选中的 JPG 文件。
    let outputURLs: [URL]

    /// 所有失败或处理不完整的项目；成功输出不回滚。
    let issues: [ImageCompressionIssue]

    /// 用户是否在完整项目之间取消了尚未处理的剩余项目。
    let wasCancelled: Bool
}

/// 压缩图片命令的完整类型化结果。
nonisolated enum ImageCompressionOutcome: Equatable, Sendable {
    /// 用户取消设置窗口；正常静默结束。
    case cancelled

    /// 批次已经执行，报告可以同时包含成功输出和失败项目。
    case completed(ImageCompressionReport)
}

/// ImageIO 无法用抛错 API 表达时使用的稳定功能错误。
nonisolated private enum ImageCompressionProcessingError: LocalizedError {
    /// 选中的文件不能创建有效 ImageIO source。
    case invalidImageSource

    /// 容器没有可以处理的主图像或第一帧。
    case missingPrimaryImage

    /// ImageIO 没有提供计算目标尺寸所需的像素属性。
    case missingImageProperties

    /// ImageIO 无法生成带正确视觉方向的缩略图。
    case thumbnailCreationFailed

    /// Core Graphics 无法创建白色背景 RGB 输出位图。
    case bitmapCreationFailed

    /// ImageIO 无法创建或完成 JPEG 编码器。
    case jpegEncodingFailed

    /// 区分源读取与输出编码，供批量日志保留准确阶段。
    var stage: ImageCompressionIssueStage {
        switch self {
        case .invalidImageSource,
             .missingPrimaryImage,
             .missingImageProperties,
             .thumbnailCreationFailed:
            return .decode
        case .bitmapCreationFailed, .jpegEncodingFailed:
            return .encode
        }
    }

    /// 对应错误的稳定本地说明。
    var errorDescription: String? {
        switch self {
        case .invalidImageSource:
            return "无法读取图片容器。"
        case .missingPrimaryImage:
            return "图片容器中没有可处理的主图像。"
        case .missingImageProperties:
            return "无法读取图片像素尺寸。"
        case .thumbnailCreationFailed:
            return "无法按目标宽度解码图片。"
        case .bitmapCreationFailed:
            return "无法创建 JPG 使用的 RGB 图像。"
        case .jpegEncodingFailed:
            return "无法完成 JPG 编码。"
        }
    }
}

/// 单项要么没有输出，要么保留输出及可选的时间属性问题。
nonisolated private enum ImageCompressionItemResult {
    /// 编解码或写入失败，没有可用输出。
    case failed(ImageCompressionIssue)

    /// JPG 已写入；时间属性写入可能单独失败。
    case output(URL, fileDateIssue: ImageCompressionIssue?)
}

// MARK: - ==================== 执行管线编排 ====================

/// 在主应用中请求设置、压缩选中图片并呈现批量结果。
@MainActor
struct CompressImagesHandler: ContextCommandHandling {
    /// 请求设置，再在后台执行命令携带的非空图片选择。
    /// - Parameter command: Extension 已验证图片类型后构造的命令。
    /// - Returns: 取消或批量处理报告。
    @concurrent nonisolated func execute(
        _ command: CompressImagesCommand
    ) async -> ImageCompressionOutcome {
        await execute(command, progress: nil)
    }

    /// 在用户确认设置后开始可取消的逐图片进度。
    @concurrent nonisolated func execute(
        _ command: CompressImagesCommand,
        context: ContextCommandExecutionContext
    ) async -> ImageCompressionOutcome {
        await execute(command, progress: context.progress)
    }

    /// 共享普通调用与进度调用的数据流，进度能力保持可选。
    private nonisolated func execute(
        _ command: CompressImagesCommand,
        progress: ContextCommandProgressReporter?
    ) async -> ImageCompressionOutcome {
        let imageURLs = command.selection.urls

        guard let settings = await ImageCompressionSettingsPrompt.request() else {
            return .cancelled
        }

        if let progress {
            await progress.begin(totalUnitCount: imageURLs.count)
        }

        let plan = Self.makePlan(
            imageURLs: imageURLs,
            settings: settings,
            baseDate: Date()
        )
        let report = await Self.execute(plan, progress: progress)
        return .completed(report)
    }

    // MARK: - ==================== 纯函数：构造批量执行计划 ====================

    /// 排序输入、映射质量并按输入位置分配每秒递增的文件时间。
    /// - Parameters:
    ///   - imageURLs: 已验证且保持 Finder 顺序的源图片集合。
    ///   - settings: 用户刚刚确认的压缩设置。
    ///   - baseDate: 整个批次唯一读取的当前时间。
    /// - Returns: 不再依赖可变设置或当前时间的执行计划。
    nonisolated static func makePlan(
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
            maximumWidth: settings.maximumWidth,
            imageIOQuality: settings.imageIOQuality,
            items: sortedURLs.enumerated().map { index, sourceURL in
                ImageCompressionItemPlan(
                    sourceURL: sourceURL,
                    outputDate: baseDate.addingTimeInterval(
                        TimeInterval(index)
                    )
                )
            }
        )
    }

    // MARK: - ==================== 副作用：执行 ImageIO 批量计划 ====================

    /// 串行执行每项计划，限制峰值内存并保留部分成功结果。
    /// - Parameter plan: 已经确定顺序、设置和文件时间的不可变计划。
    /// - Returns: 成功输出与全部分类问题。
    nonisolated static func execute(
        _ plan: ImageCompressionPlan,
        progress: ContextCommandProgressReporter? = nil
    ) async -> ImageCompressionReport {
        var outputURLs: [URL] = []
        var issues: [ImageCompressionIssue] = []
        var wasCancelled = false

        for item in plan.items {
            if let progress, await progress.isCancellationRequested {
                wasCancelled = true
                break
            }
            guard !Task.isCancelled else {
                break
            }

            let result = autoreleasepool {
                execute(
                    item,
                    maximumWidth: plan.maximumWidth,
                    imageIOQuality: plan.imageIOQuality
                )
            }
            switch result {
            case .failed(let issue):
                issues.append(issue)
            case .output(let outputURL, let fileDateIssue):
                outputURLs.append(outputURL)
                if let fileDateIssue {
                    issues.append(fileDateIssue)
                }
            }
            if let progress {
                await progress.advance()
            }
        }

        return ImageCompressionReport(
            outputURLs: outputURLs,
            issues: issues,
            wasCancelled: wasCancelled
        )
    }

    /// 解码、编码并不覆盖写入一项；文件时间失败时仍保留输出。
    private nonisolated static func execute(
        _ item: ImageCompressionItemPlan,
        maximumWidth: Int,
        imageIOQuality: Double
    ) -> ImageCompressionItemResult {
        let jpegData: Data
        do {
            jpegData = try encodedJPEG(
                from: item.sourceURL,
                maximumWidth: maximumWidth,
                imageIOQuality: imageIOQuality
            )
        } catch {
            return .failed(
                issue(
                    for: error,
                    itemURL: item.sourceURL,
                    stage: (error as? ImageCompressionProcessingError)?.stage
                        ?? .decode
                )
            )
        }

        let outputURL: URL
        do {
            outputURL = try writeJPEGWithoutOverwriting(
                jpegData,
                for: item.sourceURL
            )
        } catch {
            return .failed(
                issue(
                    for: error,
                    itemURL: item.sourceURL.deletingLastPathComponent(),
                    stage: .write
                )
            )
        }

        do {
            try FileManager.default.setAttributes(
                [
                    .creationDate: item.outputDate,
                    .modificationDate: item.outputDate,
                ],
                ofItemAtPath: outputURL.path
            )
            return .output(outputURL, fileDateIssue: nil)
        } catch {
            return .output(
                outputURL,
                fileDateIssue: issue(
                    for: error,
                    itemURL: outputURL,
                    stage: .fileDates
                )
            )
        }
    }

    /// 使用主图像、视觉方向和精确目标宽度生成无源元数据的 JPG 数据。
    private nonisolated static func encodedJPEG(
        from sourceURL: URL,
        maximumWidth: Int,
        imageIOQuality: Double
    ) throws -> Data {
        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        try sourceHandle.close()

        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ImageCompressionProcessingError.invalidImageSource
        }

        let imageCount = CGImageSourceGetCount(source)
        guard imageCount > 0 else {
            throw ImageCompressionProcessingError.missingPrimaryImage
        }
        let reportedPrimaryIndex = CGImageSourceGetPrimaryImageIndex(source)
        let primaryIndex = (0..<imageCount).contains(reportedPrimaryIndex)
            ? reportedPrimaryIndex
            : 0
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                primaryIndex,
                nil
            ) as NSDictionary?,
            let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            rawWidth.intValue > 0,
            rawHeight.intValue > 0
        else {
            throw ImageCompressionProcessingError.missingImageProperties
        }

        let orientation = (
            properties[kCGImagePropertyOrientation] as? NSNumber
        )?.intValue ?? 1
        let swapsDimensions = (5...8).contains(orientation)
        let visualWidth = swapsDimensions
            ? rawHeight.intValue
            : rawWidth.intValue
        let visualHeight = swapsDimensions
            ? rawWidth.intValue
            : rawHeight.intValue
        let targetWidth = min(visualWidth, maximumWidth)
        let targetHeight = max(
            1,
            Int(
                (
                    Double(visualHeight)
                        * Double(targetWidth)
                        / Double(visualWidth)
                ).rounded()
            )
        )
        let thumbnailMaximumDimension = max(targetWidth, targetHeight)

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaximumDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            primaryIndex,
            thumbnailOptions as CFDictionary
        ) else {
            throw ImageCompressionProcessingError.thumbnailCreationFailed
        }

        guard let outputImage = opaqueImage(
            from: thumbnail,
            width: targetWidth,
            height: targetHeight
        ) else {
            throw ImageCompressionProcessingError.bitmapCreationFailed
        }

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageCompressionProcessingError.jpegEncodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            outputImage,
            [
                kCGImageDestinationLossyCompressionQuality: imageIOQuality,
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressionProcessingError.jpegEncodingFailed
        }
        return encodedData as Data
    }

    /// 把方向已修正的图片高质量绘制到白底 sRGB 位图。
    private nonisolated static func opaqueImage(
        from sourceImage: CGImage,
        width: Int,
        height: Int
    ) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return context.makeImage()
    }

    /// 以源基础名和统一冲突规则排他写入第一个可用的 JPG 名称。
    private nonisolated static func writeJPEGWithoutOverwriting(
        _ data: Data,
        for sourceURL: URL
    ) throws -> URL {
        let preferredURL = sourceURL
            .deletingPathExtension()
            .appendingPathExtension("jpg")

        for candidateURL in FileCollisionNaming.candidateURLs(
            for: preferredURL
        ) {
            do {
                try data.write(
                    to: candidateURL,
                    options: .withoutOverwriting
                )
                return candidateURL
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }

        throw CocoaError(.fileWriteFileExists)
    }

    /// 把底层错误映射为批量反馈使用的稳定问题。
    private nonisolated static func issue(
        for error: Error,
        itemURL: URL,
        stage: ImageCompressionIssueStage
    ) -> ImageCompressionIssue {
        let systemError = SystemErrorSnapshot(capturing: error)
        return ImageCompressionIssue(
            itemURL: itemURL,
            stage: stage,
            kind: FileSystemErrorKind(classifying: systemError),
            systemError: systemError
        )
    }

    // MARK: - ==================== 副作用：反馈执行结果 ====================

    /// 把最终报告交给统一反馈出口。
    func present(
        _ outcome: ImageCompressionOutcome,
        requestID: UUID
    ) {
        ImageCompressionFeedback.present(outcome, requestID: requestID)
    }
}

// MARK: - ==================== 纯函数：构造错误提示内容 ====================

/// 把压缩失败与已经生成 JPG 后的时间属性问题分别汇总。
nonisolated enum ImageCompressionAlertContent {
    static func make(
        for report: ImageCompressionReport
    ) -> CommandAlertContent? {
        let compressionIssues = report.issues.filter {
            $0.stage != .fileDates
                && ($0.kind == .permissionDenied
                    || $0.kind == .readOnlyFileSystem)
        }
        let fileDateIssues = report.issues.filter { $0.stage == .fileDates }

        var lines: [String] = []
        if !compressionIssues.isEmpty {
            let subject = CommandAlertText.subject(
                for: compressionIssues.map(\.itemURL),
                countedAs: "张图片"
            )
            let scope = report.outputURLs.isEmpty ? "" : "部分"
            lines.append(
                "无法压缩\(scope)图片：\(subject)没有写入权限。"
            )
        }

        if !fileDateIssues.isEmpty {
            let subject = CommandAlertText.subject(
                for: fileDateIssues.map(\.itemURL),
                countedAs: "张图片"
            )
            let fatalIssueCount = report.issues.count - fileDateIssues.count
            let processedCount = report.outputURLs.count + fatalIssueCount
            let scope = fileDateIssues.count < processedCount ? "部分" : ""
            lines.append(
                "\(scope)图片已压缩但遇到问题：\(subject)的时间属性写入失败。"
            )
        }

        guard !lines.isEmpty else {
            return nil
        }
        return CommandAlertContent(body: lines.joined(separator: "\n"))
    }
}

// MARK: - ==================== 副作用：选择结果、日志与用户反馈 ====================

/// 把压缩结果编排为 Finder 选择、一次日志记录和一次用户反馈。
@MainActor
private enum ImageCompressionFeedback {
    static func present(
        _ outcome: ImageCompressionOutcome,
        requestID: UUID
    ) {
        ImageCompressionOutcomeLogger.log(outcome, requestID: requestID)

        switch outcome {
        case .cancelled:
            return

        case .completed(let report):
            if !report.outputURLs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(
                    report.outputURLs
                )
            }
            guard !report.issues.isEmpty else {
                return
            }
            if let content = ImageCompressionAlertContent.make(for: report) {
                CommandAlertPresenter.present(content)
            } else {
                NSSound.beep()
            }
        }
    }
}

/// 只记录图片压缩的详细执行事实，不构造或显示弹窗。
@MainActor
private enum ImageCompressionOutcomeLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EnhancedContextMenu",
        category: "ImageCompression"
    )

    static func log(
        _ outcome: ImageCompressionOutcome,
        requestID: UUID
    ) {
        switch outcome {
        case .cancelled:
            logger.debug(
                "Cancelled image-compression request \(requestID.uuidString, privacy: .public)"
            )

        case .completed(let report):
            for issue in report.issues {
                logger.error(
                    "Image-compression failure during \(issue.stage.rawValue, privacy: .public) for request \(requestID.uuidString, privacy: .public) at \(issue.itemURL.path, privacy: .private) [\(issue.systemError.domain, privacy: .public):\(issue.systemError.code, privacy: .public)]: \(issue.systemError.localizedDescription, privacy: .private)"
                )
            }
            guard report.issues.isEmpty else {
                return
            }
            if report.wasCancelled {
                logger.info(
                    "Cancelled image compression after \(report.outputURLs.count) outputs for request \(requestID.uuidString, privacy: .public)"
                )
            } else {
                logger.info(
                    "Compressed \(report.outputURLs.count) images for request \(requestID.uuidString, privacy: .public)"
                )
            }
        }
    }
}

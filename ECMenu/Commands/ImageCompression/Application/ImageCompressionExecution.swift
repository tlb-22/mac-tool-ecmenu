/**
 按压缩计划逐项读取、转换并写出图片，汇总成功、失败与取消结果。
 通过注入的平台操作执行副作用，并在项目边界报告进度与检查取消。
 */

import Foundation

/// 单项压缩需要的三个系统边界；日期失败与完整输出分别记录。
nonisolated struct ImageCompressionPlatform: Sendable {
    let encodedJPEG: @Sendable (URL, ImageCompressionSettings) throws -> Data
    let writeJPEG: @Sendable (Data, URL) throws -> URL
    let setFileDates: @Sendable (URL, Date) throws -> Void
}

/// 在项目边界处理取消，逐项转换并排他写入，保留全部已生成输出。
nonisolated enum ImageCompressionExecution {
    static func execute(
        _ plan: ImageCompressionPlan,
        platform: ImageCompressionPlatform,
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
                execute(item, settings: plan.settings, platform: platform)
            })
            if let progress {
                await progress.advance()
            }
        }

        return ImageCompressionReport(items: items, wasCancelled: wasCancelled)
    }

    private static func execute(
        _ item: ImageCompressionItemPlan,
        settings: ImageCompressionSettings,
        platform: ImageCompressionPlatform
    ) -> ImageCompressionItemResult {
        let jpegData: Data
        do {
            jpegData = try platform.encodedJPEG(item.sourceURL, settings)
        } catch {
            return .failed(.source(
                sourceURL: item.sourceURL,
                stage: (error as? ImageCompressionProcessingError)?.stage ?? .decode,
                error: SystemErrorSnapshot(capturing: error)
            ))
        }

        let outputURL: URL
        do {
            outputURL = try platform.writeJPEG(jpegData, item.sourceURL)
        } catch {
            return .failed(.destination(
                sourceURL: item.sourceURL,
                directoryURL: item.sourceURL.deletingLastPathComponent(),
                error: SystemErrorSnapshot(capturing: error)
            ))
        }

        let fileDateError: SystemErrorSnapshot?
        do {
            try platform.setFileDates(outputURL, item.outputDate)
            fileDateError = nil
        } catch {
            fileDateError = SystemErrorSnapshot(capturing: error)
        }
        return .output(ImageCompressionOutput(url: outputURL, fileDateError: fileDateError))
    }
}

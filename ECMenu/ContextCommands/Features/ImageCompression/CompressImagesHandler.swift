import Foundation

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

        let plan = ImageCompressionPlan.make(
            imageURLs: imageURLs,
            settings: settings,
            baseDate: Date()
        )
        let report = await ImageCompressionExecution.execute(plan, progress: progress)
        return .completed(report)
    }

    /// 在主线程统一选择输出并反馈批量结果。
    func present(_ outcome: ImageCompressionOutcome, requestID: UUID) {
        ImageCompressionFeedback.present(outcome, requestID: requestID)
    }
}

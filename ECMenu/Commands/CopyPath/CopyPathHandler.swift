/**
 协调路径存在性读取、复制计划生成与主执行器上的剪贴板写入。
 在同一次主执行器调用中检查取消并执行写入，再交由注入的反馈入口呈现结果。
 */

import Foundation

/// 系统事实读取与 MainActor 剪贴板写入的窄边界。
nonisolated struct CopyPathPlatform: Sendable {
    let existingURLs: @Sendable ([AbsoluteFilePath]) -> Set<URL>
    let writeString: @MainActor @Sendable (String) -> Bool
}

@MainActor
struct CopyPathHandler: ContextCommandHandling {
    private let platform: CopyPathPlatform
    private let feedback: @MainActor @Sendable (CopyPathOutcome, UUID) -> Void

    nonisolated init(
        platform: CopyPathPlatform,
        present: @escaping @MainActor @Sendable (CopyPathOutcome, UUID) -> Void
    ) {
        self.platform = platform
        feedback = present
    }

    @concurrent nonisolated func execute(
        _ command: CopyPathCommand
    ) async -> CopyPathOutcome {
        let plan: CopyPathPlan
        switch CopyPathRules.makePlan(
            for: command,
            existingURLs: platform.existingURLs(command.paths)
        ) {
        case .failure(let failure): return .failure(failure)
        case .success(let value): plan = value
        }
        return await write(plan)
    }

    /// 取消检查和同步 AppKit 写入处于同一次主执行器调用，保持取消任务不写剪贴板。
    private func write(_ plan: CopyPathPlan) -> CopyPathOutcome {
        guard !Task.isCancelled else { return .cancelled }
        guard platform.writeString(plan.pasteboardString) else {
            return .failure(.pasteboardWriteFailed)
        }
        return .success(CopyPathSuccess(itemCount: plan.itemURLs.count))
    }

    func present(_ outcome: CopyPathOutcome, requestID: UUID) {
        feedback(outcome, requestID)
    }
}

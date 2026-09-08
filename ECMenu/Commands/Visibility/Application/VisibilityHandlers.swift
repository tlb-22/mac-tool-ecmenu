/**
 将隐藏和显示命令映射到共用可见性执行流程。
 通过命令协议确定操作方向，并连接平台能力与结果反馈。
 */

import Foundation

/// 把共享命令类型静态绑定到需要达到的隐藏状态。
nonisolated protocol VisibilityCommand: ContextCommandPayload {
    /// 命令携带的非空 Finder 选择。
    var selection: FinderItemSelection { get }

    /// 该命令要求的固定操作。
    static var operation: VisibilityOperation { get }
}

extension HideItemsCommand: VisibilityCommand {
    static var operation: VisibilityOperation { .hide }
}

extension ShowItemsCommand: VisibilityCommand {
    static var operation: VisibilityOperation { .show }
}

/// 使用具体命令类型决定隐藏或显示的共享 Handler。
@MainActor
struct VisibilityHandler<Command: VisibilityCommand>: ContextCommandHandling {
    private let platform: VisibilityPlatform
    private let feedback: @MainActor @Sendable (VisibilityReport, VisibilityOperation, UUID) -> Void

    nonisolated init(
        platform: VisibilityPlatform,
        present: @escaping @MainActor @Sendable (VisibilityReport, VisibilityOperation, UUID) -> Void
    ) {
        self.platform = platform
        feedback = present
    }

    /// 在通用执行器中逐项写入隐藏属性。
    @concurrent nonisolated func execute(
        _ command: Command
    ) async -> VisibilityReport {
        VisibilityExecution.execute(
            selection: command.selection,
            operation: Command.operation,
            platform: platform
        )
    }

    /// 使用命令类型绑定的操作呈现统一反馈。
    func present(_ report: VisibilityReport, requestID: UUID) {
        feedback(report, Command.operation, requestID)
    }
}

typealias HideItemsHandler = VisibilityHandler<HideItemsCommand>
typealias ShowItemsHandler = VisibilityHandler<ShowItemsCommand>

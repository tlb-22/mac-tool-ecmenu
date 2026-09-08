/**
 为在外部应用中打开的各类命令提供共用处理器。
 将具体命令的应用要求带入执行流程，并把结果交给注入的反馈入口。
 */

import Foundation

/// 由具体命令类型提供固定应用和目标约束的共享 Handler。
@MainActor
struct OpenInApplicationHandler<Command: OpenInApplicationCommand>:
    ContextCommandHandling
{
    private let platform: OpenInApplicationPlatform
    private let feedback: @MainActor @Sendable (OpenInApplicationOutcome, String, UUID) -> Void

    nonisolated init(
        platform: OpenInApplicationPlatform,
        present: @escaping @MainActor @Sendable (OpenInApplicationOutcome, String, UUID) -> Void
    ) {
        self.platform = platform
        feedback = present
    }

    /// 执行命令类型完整声明的单目标外部应用管线。
    @concurrent nonisolated func execute(
        _ command: Command
    ) async -> OpenInApplicationOutcome {
        await OpenInApplicationExecution.execute(command, platform: platform)
    }

    /// 使用同一命令声明的产品名称呈现结果。
    func present(_ outcome: OpenInApplicationOutcome, requestID: UUID) {
        feedback(outcome, Command.applicationRequirement.displayName, requestID)
    }
}

typealias OpenInVSCodeHandler = OpenInApplicationHandler<OpenInVSCodeCommand>
typealias OpenInITerm2Handler = OpenInApplicationHandler<OpenInITerm2Command>

import Foundation

/// 由具体命令类型提供固定应用和目标约束的共享 Finder Feature。
final class OpenInApplicationFeature<Command: OpenInApplicationCommand>:
    SingleActionContextMenuFeature
{
    /// 向主应用投递当前类型命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 注入跨进程命令客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    /// 只为仍然存在且符合命令种类约束的单一目标构造命令。
    func command(
        in context: FinderContextMenuEvaluationContext
    ) -> Command? {
        guard case .existing(let targetPath, let kind) = context.singleTarget else {
            return nil
        }
        guard !Command.targetKind.requiresDirectory || kind == .directory else {
            return nil
        }
        return Command(targetPath: targetPath)
    }
}

typealias OpenInVSCodeFeature = OpenInApplicationFeature<OpenInVSCodeCommand>
typealias OpenInITerm2Feature = OpenInApplicationFeature<OpenInITerm2Command>

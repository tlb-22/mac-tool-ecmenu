/// 新建 TXT 功能在 Finder Extension 中的可用性与命令发送端。
final class CreateNewTextFileFeature: SingleActionContextMenuFeature {
    /// 为菜单身份和跨进程负载提供唯一的共享命令类型。
    typealias Command = CreateNewTextFileCommand

    /// 向主应用投递新建 TXT 命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 注入跨进程命令客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    // MARK: - ==================== 纯函数：菜单策略与命令构造 ====================

    /// 根据 Finder 当前上下文决定是否显示功能。
    func isAvailable(in context: FinderContextMenuEvaluationContext) -> Bool {
        switch context.snapshot {
        case .container, .sidebar:
            return true
        case .items(let selection):
            return selection.paths.count == 1
        }
    }

    /// 使用当前菜单项在构建时绑定的 Finder 状态构造新建 TXT 命令。
    func command(for snapshot: FinderContextSnapshot) -> CreateNewTextFileCommand {
        CreateNewTextFileCommand(finderContext: snapshot)
    }
}

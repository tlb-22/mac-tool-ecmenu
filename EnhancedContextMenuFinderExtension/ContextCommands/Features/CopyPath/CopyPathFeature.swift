/// 拷贝路径功能在 Finder Extension 中的可用性与命令发送端。
final class CopyPathFeature: SingleActionContextMenuFeature {
    /// 为菜单身份和跨进程负载提供唯一的共享命令类型。
    typealias Command = CopyPathCommand

    /// 向主应用投递拷贝路径命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 注入跨进程命令客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    // MARK: - ==================== 纯函数：菜单策略与命令构造 ====================

    /// 在空白处、侧边栏或非空选择集合中显示命令。
    func isAvailable(in context: FinderContextMenuEvaluationContext) -> Bool {
        true
    }

    /// 使用当前菜单项在构建时绑定的 Finder 状态构造拷贝路径命令。
    func command(for snapshot: FinderContextSnapshot) -> CopyPathCommand {
        CopyPathCommand(finderContext: snapshot)
    }
}

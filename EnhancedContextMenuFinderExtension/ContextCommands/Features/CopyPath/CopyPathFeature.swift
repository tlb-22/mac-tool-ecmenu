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

    /// 把当前菜单的非空绝对路径集合固化到命令中。
    func command(
        in context: FinderContextMenuEvaluationContext
    ) -> CopyPathCommand? {
        CopyPathCommand(paths: context.snapshot.absolutePaths)
    }
}

/**
 将菜单构建时固定的语义路径转换为拷贝路径动作，保持 Finder 提供的非空路径顺序。
 此处只准备发送参数，路径对象检查与剪贴板写入由主应用执行边界完成。
 */

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

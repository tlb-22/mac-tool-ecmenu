import Foundation

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

    /// 菜单期把唯一候选解析为实际写入目录。
    func command(
        in context: FinderContextMenuEvaluationContext
    ) -> CreateNewTextFileCommand? {
        guard let directoryPath = Self.directoryPath(in: context) else {
            return nil
        }
        return CreateNewTextFileCommand(directoryPath: directoryPath)
    }

    /// 跟随符号链接重验目标，并把单个文件归一到父目录。
    private static func directoryPath(
        in context: FinderContextMenuEvaluationContext
    ) -> AbsoluteFilePath? {
        guard case .existing(let targetPath, let kind) = context.singleTarget else {
            return nil
        }

        switch context.snapshot {
        case .container, .sidebar:
            return kind == .directory ? targetPath : nil
        case .items:
            if kind == .directory {
                return targetPath
            }
            return AbsoluteFilePath(
                url: targetPath.url.deletingLastPathComponent()
            )
        }
    }
}

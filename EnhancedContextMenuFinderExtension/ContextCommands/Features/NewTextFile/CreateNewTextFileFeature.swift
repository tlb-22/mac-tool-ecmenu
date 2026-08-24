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
        guard let directoryPath = Self.directoryPath(
            for: context.snapshot
        ) else {
            return nil
        }
        return CreateNewTextFileCommand(directoryPath: directoryPath)
    }

    /// 跟随符号链接重验目标，并把单个文件归一到父目录。
    private static func directoryPath(
        for snapshot: FinderContextSnapshot
    ) -> AbsoluteFilePath? {
        guard snapshot.absolutePaths.count == 1,
              let targetPath = snapshot.absolutePaths.first else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: targetPath.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }

        switch snapshot {
        case .container, .sidebar:
            return isDirectory.boolValue ? targetPath : nil
        case .items:
            if isDirectory.boolValue {
                return targetPath
            }
            return AbsoluteFilePath(
                url: targetPath.url.deletingLastPathComponent()
            )
        }
    }
}

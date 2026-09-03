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
        guard let targetPath = OpenInApplicationFinderFacts.targetPath(
            for: context.snapshot,
            kind: Command.targetKind
        ) else {
            return nil
        }
        return Command(targetPath: targetPath)
    }
}

typealias OpenInVSCodeFeature = OpenInApplicationFeature<OpenInVSCodeCommand>
typealias OpenInITerm2Feature = OpenInApplicationFeature<OpenInITerm2Command>

// MARK: - ==================== Finder 系统事实边界 ====================

/// 读取外部应用菜单目标所需的 Finder 与文件系统事实。
private enum OpenInApplicationFinderFacts {
    /// 重验单一候选的存在性和命令声明的目标种类。
    static func targetPath(
        for snapshot: FinderContextSnapshot,
        kind: OpenInApplicationTargetKind
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
        guard !kind.requiresDirectory || isDirectory.boolValue else {
            return nil
        }
        return targetPath
    }
}

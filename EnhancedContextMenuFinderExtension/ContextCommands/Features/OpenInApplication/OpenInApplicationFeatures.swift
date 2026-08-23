import Foundation

// MARK: - ==================== VS Code Feature ====================

/// VS Code 功能在 Finder Extension 中的可用性与命令发送端。
final class OpenInVSCodeFeature: SingleActionContextMenuFeature {
    /// 为菜单身份、应用依赖和跨进程负载提供共享命令类型。
    typealias Command = OpenInVSCodeCommand

    /// 向主应用投递 VS Code 命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 注入跨进程命令客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    /// 在目录空白处、侧边栏目录或任意一个有效选中对象上显示。
    func isAvailable(in context: FinderContextMenuEvaluationContext) -> Bool {
        OpenInApplicationFinderFacts.targetURL(
            for: context.snapshot,
            requiresDirectory: false
        ) != nil
    }

    /// 使用当前菜单项在构建时绑定的 Finder 状态构造 VS Code 命令。
    func command(for snapshot: FinderContextSnapshot) -> OpenInVSCodeCommand {
        OpenInVSCodeCommand(finderContext: snapshot)
    }
}

// MARK: - ==================== iTerm2 Feature ====================

/// iTerm2 功能在 Finder Extension 中的可用性与命令发送端。
final class OpenInITerm2Feature: SingleActionContextMenuFeature {
    /// 为菜单身份、应用依赖和跨进程负载提供共享命令类型。
    typealias Command = OpenInITerm2Command

    /// 向主应用投递 iTerm2 命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 注入跨进程命令客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    /// 只在目录空白处、侧边栏目录或单个目录对象上显示。
    func isAvailable(in context: FinderContextMenuEvaluationContext) -> Bool {
        OpenInApplicationFinderFacts.targetURL(
            for: context.snapshot,
            requiresDirectory: true
        ) != nil
    }

    /// 使用当前菜单项在构建时绑定的 Finder 状态构造 iTerm2 命令。
    func command(for snapshot: FinderContextSnapshot) -> OpenInITerm2Command {
        OpenInITerm2Command(finderContext: snapshot)
    }
}

// MARK: - ==================== Finder 系统事实边界 ====================

/// 读取外部应用菜单目标所需的 Finder 与文件系统事实。
private enum OpenInApplicationFinderFacts {
    /// 使用菜单构建阶段统一采集的快照解析唯一有效目标。
    static func targetURL(
        for snapshot: FinderContextSnapshot,
        requiresDirectory: Bool
    ) -> URL? {
        var existingURLs: Set<URL> = []
        var directoryURLs: Set<URL> = []

        for url in snapshot.urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ) else {
                continue
            }
            let normalizedURL = url.standardizedFileURL
            existingURLs.insert(normalizedURL)
            if isDirectory.boolValue {
                directoryURLs.insert(normalizedURL)
            }
        }

        return OpenInApplicationTargetResolver.targetURL(
            for: snapshot,
            existingURLs: existingURLs,
            directoryURLs: directoryURLs,
            requiresDirectory: requiresDirectory
        )
    }
}

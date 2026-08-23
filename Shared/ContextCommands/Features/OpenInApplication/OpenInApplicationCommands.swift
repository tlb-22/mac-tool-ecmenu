import Foundation

/// 请求主应用把 Finder 的单一目标交给 Visual Studio Code。
nonisolated struct OpenInVSCodeCommand: ContextCommandPayload, Equatable {
    /// VS Code 命令唯一一份稳定身份、产品名称、菜单图标和应用依赖。
    static let descriptor = ContextCommandDescriptor(
        id: "open-in-vscode",
        title: "进入 Visual Studio Code",
        icon: .requiredApplication,
        requiredApplication: ContextCommandApplicationRequirement(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "Visual Studio Code"
        )
    )

    /// Extension 在 Finder 请求菜单时冻结的上下文。
    let finderContext: FinderContextSnapshot

    /// 创建携带指定 Finder 快照的 VS Code 命令。
    init(finderContext: FinderContextSnapshot) {
        self.finderContext = finderContext
    }
}

/// 请求主应用让 iTerm2 进入 Finder 的单一目录目标。
nonisolated struct OpenInITerm2Command: ContextCommandPayload, Equatable {
    /// iTerm2 命令唯一一份稳定身份、产品名称、菜单图标和应用依赖。
    static let descriptor = ContextCommandDescriptor(
        id: "open-in-iterm2",
        title: "进入 iTerm2",
        icon: .requiredApplication,
        requiredApplication: ContextCommandApplicationRequirement(
            bundleIdentifier: "com.googlecode.iterm2",
            displayName: "iTerm2"
        )
    )

    /// Extension 在 Finder 请求菜单时冻结的上下文。
    let finderContext: FinderContextSnapshot

    /// 创建携带指定 Finder 快照的 iTerm2 命令。
    init(finderContext: FinderContextSnapshot) {
        self.finderContext = finderContext
    }
}

/// 只依据 Finder 快照和已读取的文件系统事实解析外部应用目标。
nonisolated enum OpenInApplicationTargetResolver {
    /// 解析单选或目录上下文中的唯一目标。
    /// - Parameters:
    ///   - snapshot: Finder 请求菜单时冻结的上下文。
    ///   - existingURLs: 跟随符号链接后仍然存在的 URL 集合。
    ///   - directoryURLs: 跟随符号链接后指向目录的 URL 集合。
    ///   - requiresDirectory: 目标是否必须是目录。
    /// - Returns: 应交给外部应用的原始 URL；上下文无效时为 `nil`。
    static func targetURL(
        for snapshot: FinderContextSnapshot,
        existingURLs: Set<URL>,
        directoryURLs: Set<URL>,
        requiresDirectory: Bool
    ) -> URL? {
        let existingURLs = Set(existingURLs.map(\.standardizedFileURL))
        let directoryURLs = Set(directoryURLs.map(\.standardizedFileURL))
        let candidate: URL?

        switch snapshot {
        case .container(let path), .sidebar(let path):
            candidate = URL(fileURLWithPath: path)

        case .items(let selection):
            guard selection.urls.count == 1 else {
                return nil
            }
            candidate = selection.urls.first
        }

        guard let targetURL = candidate?.standardizedFileURL,
              existingURLs.contains(targetURL),
              !requiresDirectory || directoryURLs.contains(targetURL) else {
            return nil
        }
        return targetURL
    }
}

import Foundation

/// 外部应用命令允许的目标种类。
nonisolated enum OpenInApplicationTargetKind: Equatable, Sendable {
    /// 文件或目录都可以成为目标。
    case item

    /// 只有当前仍然存在的目录可以成为目标。
    case directory

    /// 执行期是否必须重新确认目录类型。
    var requiresDirectory: Bool { self == .directory }
}

/// 由具体类型完整声明应用依赖和目标约束的外部应用命令。
nonisolated protocol OpenInApplicationCommand: ContextCommandPayload {
    /// 由一个值绑定产品身份、应用依赖和目标约束。
    static var definition: OpenInApplicationCommandDefinition { get }

    /// 菜单期解析出的唯一绝对目标路径。
    var targetPath: AbsoluteFilePath { get }

    /// 创建携带唯一目标的具体命令。
    init(targetPath: AbsoluteFilePath)
}

/// 把外部应用命令的展示、依赖和目标规则绑定为单一声明。
nonisolated struct OpenInApplicationCommandDefinition: Equatable, Sendable {
    /// 路由和配置使用的稳定功能身份。
    private let featureID: ContextCommandFeatureID

    /// Finder 菜单和主应用界面共用的产品名称。
    private let title: LocalizedStringResource

    /// Launch Services 需要定位的固定应用。
    let applicationRequirement: ContextCommandApplicationRequirement

    /// 该命令接受的目标种类。
    let targetKind: OpenInApplicationTargetKind

    /// 由唯一应用依赖派生菜单图标，不另存一份可能分歧的状态。
    var descriptor: ContextCommandDescriptor {
        ContextCommandDescriptor(
            id: featureID.rawValue,
            title: title,
            icon: .application(applicationRequirement)
        )
    }

    /// 创建一个图标与执行依赖不可能分歧的外部应用声明。
    init(
        id: String,
        title: LocalizedStringResource,
        applicationRequirement: ContextCommandApplicationRequirement,
        targetKind: OpenInApplicationTargetKind
    ) {
        precondition(!title.key.isEmpty)
        featureID = ContextCommandFeatureID(rawValue: id)
        self.title = title
        self.applicationRequirement = applicationRequirement
        self.targetKind = targetKind
    }
}

extension OpenInApplicationCommand {
    /// `ContextCommandPayload` 使用的身份由同一外部应用声明派生。
    nonisolated static var descriptor: ContextCommandDescriptor {
        definition.descriptor
    }

    /// 执行端使用的应用与 descriptor 图标始终来自同一个值。
    nonisolated static var applicationRequirement: ContextCommandApplicationRequirement {
        definition.applicationRequirement
    }

    /// 菜单端与执行端共用同一目标约束。
    nonisolated static var targetKind: OpenInApplicationTargetKind {
        definition.targetKind
    }
}

/// 请求主应用把 Finder 的单一目标交给 Visual Studio Code。
nonisolated struct OpenInVSCodeCommand: OpenInApplicationCommand, Equatable {
    /// VS Code 命令的单一产品与执行声明。
    static let definition = OpenInApplicationCommandDefinition(
        id: "open-in-vscode",
        title: LocalizedStringResource(
            "command.openInVisualStudioCode",
            defaultValue: "Open in Visual Studio Code",
            comment: "Finder command that opens the target in Visual Studio Code"
        ),
        applicationRequirement: ContextCommandApplicationRequirement(
            bundleIdentifier: "com.microsoft.VSCode",
            displayName: "Visual Studio Code"
        ),
        targetKind: .item
    )

    /// 菜单期解析出的唯一目标。
    let targetPath: AbsoluteFilePath

    /// 创建携带指定目标的 VS Code 命令。
    init(targetPath: AbsoluteFilePath) {
        self.targetPath = targetPath
    }
}

/// 请求主应用让 iTerm2 进入 Finder 的单一目录目标。
nonisolated struct OpenInITerm2Command: OpenInApplicationCommand, Equatable {
    /// iTerm2 命令的单一产品与执行声明。
    static let definition = OpenInApplicationCommandDefinition(
        id: "open-in-iterm2",
        title: LocalizedStringResource(
            "command.openInITerm2",
            defaultValue: "Open in iTerm2",
            comment: "Finder command that opens the target directory in iTerm2"
        ),
        applicationRequirement: ContextCommandApplicationRequirement(
            bundleIdentifier: "com.googlecode.iterm2",
            displayName: "iTerm2"
        ),
        targetKind: .directory
    )

    /// 菜单期解析出的唯一目录目标。
    let targetPath: AbsoluteFilePath

    /// 创建携带指定目录目标的 iTerm2 命令。
    init(targetPath: AbsoluteFilePath) {
        self.targetPath = targetPath
    }
}

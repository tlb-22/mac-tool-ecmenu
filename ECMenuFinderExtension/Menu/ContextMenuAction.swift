/**
 定义菜单叶子的局部身份、复合身份、标题与图标描述，以及从求值上下文生成命令的闭包。
 这些值连接能力声明与通用菜单运行时，并区分产品本地化文案和用户原样显示的名称。
 */

import Foundation

/// 一个 Action 在所属 Feature 内的稳定局部身份。
nonisolated struct ContextMenuActionLocalID: Hashable, Sendable {
    /// Feature 声明内保持唯一的字符串。
    let rawValue: String

    /// 验证并保存局部 Action 标识。
    init(rawValue: String) {
        precondition(!rawValue.isEmpty)
        self.rawValue = rawValue
    }
}

/// Finder 菜单运行时用于唯一定位一个具体 Action 的复合身份。
nonisolated struct FinderContextMenuActionID: Hashable, Sendable {
    /// 持久化配置仍然使用的功能级身份。
    let featureID: ContextCommandFeatureID

    /// Feature 菜单树中的具体叶子身份。
    let localID: ContextMenuActionLocalID
}

/// 区分产品本地化文案和必须原样显示的用户名称。
nonisolated enum ContextMenuActionTitle: Equatable, Sendable {
    case localized(LocalizedStringResource)
    case verbatim(String)

    var string: String {
        switch self {
        case .localized(let resource):
            String(localized: resource)
        case .verbatim(let value):
            value
        }
    }
}

/// Finder 渲染一个具体 Action 所需的无框架值。
nonisolated struct FinderContextMenuActionDescriptor: Equatable, Sendable {
    /// 功能身份与局部 Action 身份组成的运行时键。
    let id: FinderContextMenuActionID

    /// Finder 菜单叶子显示的名称。
    let title: ContextMenuActionTitle

    /// Finder 菜单叶子显示的可选图标来源。
    let icon: ContextCommandIcon?

    /// 所属命令声明的运行依赖，不由具体菜单叶子的图标决定。
    let requiredApplication: ContextCommandApplicationRequirement?
}

/// 一个 Feature 内声明的类型化菜单叶子。
struct ContextMenuAction<Command: ContextCommandPayload> {
    /// Feature 内唯一的局部身份。
    let id: ContextMenuActionLocalID

    /// 产品本地化名称或用户定义的模板显示名。
    let title: ContextMenuActionTitle

    /// 菜单叶子的可选图标来源。
    let icon: ContextCommandIcon?

    /// 构造可执行命令；当前上下文不可用时返回 `nil`。
    let command: (FinderContextMenuEvaluationContext) -> Command?

    /// 声明一个类型化菜单 Action。
    /// - Parameters:
    ///   - id: Feature 内保持稳定且唯一的局部标识。
    ///   - title: Finder 显示的叶子名称。
    ///   - icon: Finder 显示的图标来源；省略时只显示文字。
    ///   - command: 从本次求值上下文创建类型化命令。
    init(
        id: String,
        title: LocalizedStringResource,
        icon: ContextCommandIcon? = nil,
        command: @escaping (FinderContextMenuEvaluationContext) -> Command?
    ) {
        self.init(
            id: id,
            title: .localized(title),
            icon: icon,
            command: command
        )
    }

    /// 显式区分动态用户名称与本地化资源。
    init(
        id: String,
        title: ContextMenuActionTitle,
        icon: ContextCommandIcon? = nil,
        command: @escaping (FinderContextMenuEvaluationContext) -> Command?
    ) {
        switch title {
        case .localized(let resource):
            precondition(!resource.key.isEmpty)
        case .verbatim(let value):
            precondition(!value.isEmpty)
        }
        if case .systemSymbol(let name)? = icon {
            precondition(!name.isEmpty)
        }

        self.id = ContextMenuActionLocalID(rawValue: id)
        self.title = title
        self.icon = icon
        self.command = command
    }
}

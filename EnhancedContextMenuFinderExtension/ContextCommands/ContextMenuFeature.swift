import Foundation
import FinderSync
import OSLog

/// 集中读取并解释 FinderSync 的瞬时菜单状态。
enum FinderContextReader {
    /// 在 Finder 菜单构建边界把原始目标字段解释为语义快照。
    ///
    /// container 回调可能把当前可见目录放入 `selectedItemURLs`，同时让
    /// `targetedURL` 停留在残余选中项，因此这里选择前者的第一项并以后者
    /// 回退。该框架差异不会继续暴露给具体 Feature 或主应用 Handler。
    /// - Parameter context: Finder 正在构建的菜单种类。
    /// - Returns: 完整语义所需路径存在时返回快照，否则返回 `nil`。
    static func snapshot(for context: FinderMenuContext) -> FinderContextSnapshot? {
        let finder = FIFinderSyncController.default()
        let targetedURL = finder.targetedURL()
        let selectedURLs = finder.selectedItemURLs() ?? []

        return snapshot(
            for: context,
            targetedURL: targetedURL,
            selectedURLs: selectedURLs
        )
    }

    /// 纯粹解释一次已经读取的 Finder 原始状态，供边界测试覆盖字段差异。
    /// - Parameters:
    ///   - context: Finder 原始菜单种类映射后的值。
    ///   - targetedURL: `FIFinderSyncController.targetedURL()` 的返回值。
    ///   - selectedURLs: `selectedItemURLs()` 的返回值或空数组。
    /// - Returns: 不含无效字段组合的语义快照。
    nonisolated static func snapshot(
        for context: FinderMenuContext,
        targetedURL: URL?,
        selectedURLs: [URL]
    ) -> FinderContextSnapshot? {
        switch context {
        case .container:
            guard let directoryURL = selectedURLs.first ?? targetedURL else {
                return nil
            }
            return .container(
                path: directoryURL.standardizedFileURL.path
            )

        case .items:
            guard let selection = FinderItemSelection(urls: selectedURLs) else {
                return nil
            }
            return .items(selection: selection)

        case .sidebar:
            guard let directoryURL = targetedURL else {
                return nil
            }
            return .sidebar(
                path: directoryURL.standardizedFileURL.path
            )
        }
    }
}

/// 一个可以声明 Finder 菜单树并构造类型化命令的增量右键功能。
protocol ContextMenuFeature: AnyObject {
    /// 当前 Feature 的所有 Action 共用的跨进程命令类型。
    associatedtype Command: ContextCommandPayload

    /// 向主应用投递当前功能命令的稳定客户端。
    var commandClient: ContextCommandClient { get }

    /// 当前 Feature 独立拥有的叶子 Action、顺序和递归层级。
    var menu: ContextMenuFeatureMenu<Command> { get }
}

/// 一次 Finder 菜单构建独占的求值上下文。
///
/// Feature 可以在这里共享构建菜单所需的系统事实。实例只存活于本次同步
/// 渲染，不随 `NSMenuItem` 或 action 快照保留，因此不会把文件状态缓存到
/// 下一次右键菜单。
final class FinderContextMenuEvaluationContext {
    /// 本次菜单构建开始时冻结的 Finder 语义。
    let snapshot: FinderContextSnapshot

    /// 按事实值类型保存本次构建已经读取的结果。
    private var factsByType: [ObjectIdentifier: Any] = [:]

    /// 为一份冻结快照创建短生命周期求值上下文。
    /// - Parameter snapshot: 本次菜单实例唯一对应的 Finder 快照。
    init(snapshot: FinderContextSnapshot) {
        self.snapshot = snapshot
    }

    /// 在本次菜单构建中至多读取一次指定类型的事实。
    /// - Parameters:
    ///   - type: 在一次构建中唯一标识这类事实的值类型。
    ///   - read: 尚无缓存时执行的同步系统事实读取。
    /// - Returns: 本次首次读取或随后复用的同一事实值。
    func fact<Fact>(
        _ type: Fact.Type,
        read: () -> Fact
    ) -> Fact {
        let key = ObjectIdentifier(type)
        if let cached = factsByType[key] as? Fact {
            return cached
        }

        let value = read()
        factsByType[key] = value
        return value
    }
}

/// 只有一个菜单 Action 的 Feature 使用的简洁协议。
///
/// 现有简单功能只需声明可用性和命令构造；默认实现会用共享
/// Command descriptor 生成唯一 Action。需要多个参数化 Action 的 Feature
/// 则直接遵循 `ContextMenuFeature` 并声明自己的 `menu`。
protocol SingleActionContextMenuFeature: ContextMenuFeature {
    /// 使用冻结快照和本次菜单共享事实判断功能是否出现。
    func isAvailable(in context: FinderContextMenuEvaluationContext) -> Bool

    /// 从菜单实例绑定的 Finder 快照构造类型化命令。
    func command(for snapshot: FinderContextSnapshot) -> Command
}

extension SingleActionContextMenuFeature {
    /// 从共享 descriptor 自动生成单一叶子，保持简单 Feature 的声明紧凑。
    var menu: ContextMenuFeatureMenu<Command> {
        let descriptor = Command.descriptor
        return ContextMenuFeatureMenu {
            ContextMenuAction(
                id: "primary",
                title: descriptor.title,
                icon: descriptor.icon,
                requiredApplication: descriptor.requiredApplication,
                isAvailable: { [self] context in
                    isAvailable(in: context)
                },
                command: { [self] snapshot in
                    command(for: snapshot)
                }
            )
        }
    }
}

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

/// Finder 渲染一个具体 Action 所需的无框架值。
nonisolated struct FinderContextMenuActionDescriptor: Equatable, Sendable {
    /// 功能身份与局部 Action 身份组成的运行时键。
    let id: FinderContextMenuActionID

    /// Finder 菜单叶子显示的名称。
    let title: String

    /// Finder 菜单叶子显示的图标来源。
    let icon: ContextCommandIcon

    /// 图标或可用性判断依赖的固定应用；没有依赖时为 `nil`。
    let requiredApplication: ContextCommandApplicationRequirement?
}

/// 一个 Feature 内声明的类型化菜单叶子。
struct ContextMenuAction<Command: ContextCommandPayload> {
    /// Feature 内唯一的局部身份。
    let id: ContextMenuActionLocalID

    /// 菜单叶子的产品名称。
    let title: String

    /// 菜单叶子的图标来源。
    let icon: ContextCommandIcon

    /// 菜单叶子依赖的外部应用。
    let requiredApplication: ContextCommandApplicationRequirement?

    /// 依据冻结快照和本次菜单共享事实判断叶子是否出现。
    let isAvailable: (FinderContextMenuEvaluationContext) -> Bool

    /// 从冻结快照构造可以携带不同参数的同一种 Command。
    let command: (FinderContextSnapshot) -> Command

    /// 声明一个类型化菜单 Action。
    /// - Parameters:
    ///   - id: Feature 内保持稳定且唯一的局部标识。
    ///   - title: Finder 显示的叶子名称。
    ///   - icon: Finder 显示的图标来源。
    ///   - requiredApplication: 图标或动作依赖的固定应用。
    ///   - isAvailable: 当前上下文是否显示该叶子。
    ///   - command: 从同一构建快照创建类型化命令，可写入 Action 参数。
    init(
        id: String,
        title: String,
        icon: ContextCommandIcon,
        requiredApplication: ContextCommandApplicationRequirement? = nil,
        isAvailable: @escaping (FinderContextMenuEvaluationContext) -> Bool = { _ in true },
        command: @escaping (FinderContextSnapshot) -> Command
    ) {
        precondition(!title.isEmpty)
        switch icon {
        case .systemSymbol(let name):
            precondition(!name.isEmpty)
        case .requiredApplication:
            precondition(requiredApplication != nil)
        }

        self.id = ContextMenuActionLocalID(rawValue: id)
        self.title = title
        self.icon = icon
        self.requiredApplication = requiredApplication
        self.isAvailable = isAvailable
        self.command = command
    }
}

/// Feature 菜单 result builder 拼接布局和 Action 时使用的中间值。
struct ContextMenuFeatureComponent<Command: ContextCommandPayload> {
    /// 当前声明片段产生的递归局部布局。
    let layout: [ContextMenuLayout<ContextMenuActionLocalID>]

    /// 当前声明片段按菜单顺序注册的类型化叶子。
    let actions: [ContextMenuAction<Command>]
}

/// 一个 Feature 独立拥有的声明式菜单树。
struct ContextMenuFeatureMenu<Command: ContextCommandPayload> {
    /// 引用具体 Action 局部身份的递归布局。
    let layout: [ContextMenuLayout<ContextMenuActionLocalID>]

    /// 按布局顺序保存的类型化 Action。
    let actions: [ContextMenuAction<Command>]

    /// 构造并验证一个 Feature 内的完整菜单树。
    init(
        @ContextMenuFeatureBuilder<Command> content: () -> ContextMenuFeatureComponent<Command>
    ) {
        let component = content()
        let actionIDs = component.actions.map(\.id)
        precondition(
            !actionIDs.isEmpty,
            "A Finder context-menu Feature must declare at least one Action"
        )
        precondition(
            Set(actionIDs).count == actionIDs.count,
            "A Finder context-menu Action was registered more than once in one Feature"
        )

        layout = component.layout
        actions = component.actions
    }
}

/// 在单个 Feature 中递归组合一组 Action。
struct ContextMenuFeatureSubmenu<Command: ContextCommandPayload> {
    /// 子菜单的固定产品标题。
    let title: String

    /// 子菜单内部的局部布局和类型化 Action。
    let content: ContextMenuFeatureComponent<Command>

    /// 使用同一类型化 builder 创建嵌套菜单。
    init(
        _ title: String,
        @ContextMenuFeatureBuilder<Command> content: () -> ContextMenuFeatureComponent<Command>
    ) {
        precondition(!title.isEmpty)
        self.title = title
        self.content = content()
    }
}

/// 把一个 Feature 的类型化 Action 组合为递归菜单声明。
@resultBuilder
enum ContextMenuFeatureBuilder<Command: ContextCommandPayload> {
    /// result builder 的统一中间类型。
    typealias Component = ContextMenuFeatureComponent<Command>

    /// 一个具体 Action 同时贡献叶子布局和命令构造行为。
    static func buildExpression(_ expression: ContextMenuAction<Command>) -> Component {
        ContextMenuFeatureComponent(
            layout: [.item(expression.id)],
            actions: [expression]
        )
    }

    /// 把系统分隔线加入 Feature 内部布局。
    static func buildExpression(_: ContextMenuSeparator) -> Component {
        ContextMenuFeatureComponent(layout: [.separator], actions: [])
    }

    /// 把 Feature 内部子菜单递归嵌入。
    static func buildExpression(
        _ expression: ContextMenuFeatureSubmenu<Command>
    ) -> Component {
        ContextMenuFeatureComponent(
            layout: [
                .submenu(
                    title: expression.title,
                    children: expression.content.layout
                ),
            ],
            actions: expression.content.actions
        )
    }

    /// 按书写顺序拼接同级布局和 Action。
    static func buildBlock(_ components: Component...) -> Component {
        ContextMenuFeatureComponent(
            layout: components.flatMap(\.layout),
            actions: components.flatMap(\.actions)
        )
    }

    /// 支持根据产品编译条件省略一段 Action 声明。
    static func buildOptional(_ component: Component?) -> Component {
        component ?? ContextMenuFeatureComponent(layout: [], actions: [])
    }

    /// 支持声明中的第一个条件分支。
    static func buildEither(first component: Component) -> Component {
        component
    }

    /// 支持声明中的第二个条件分支。
    static func buildEither(second component: Component) -> Component {
        component
    }

    /// 支持以循环生成同级 Action。
    static func buildArray(_ components: [Component]) -> Component {
        ContextMenuFeatureComponent(
            layout: components.flatMap(\.layout),
            actions: components.flatMap(\.actions)
        )
    }
}

/// 隐藏具体 Command 类型，供稳定菜单运行时统一存储和调用一个 Action。
final class AnyContextMenuAction {
    /// 具体叶子的完整身份和展示信息。
    let descriptor: FinderContextMenuActionDescriptor

    /// 类型擦除后的 Finder 上下文可用性判断。
    private let isAvailableClosure: (FinderContextMenuEvaluationContext) -> Bool

    /// 类型擦除后的命令构造和发送行为。
    private let performClosure: (FinderContextSnapshot) -> Void

    /// 为一个 Feature 的具体叶子绑定共享命令类型和投递客户端。
    init<Command: ContextCommandPayload>(
        _ action: ContextMenuAction<Command>,
        featureID: ContextCommandFeatureID,
        commandClient: ContextCommandClient
    ) {
        descriptor = FinderContextMenuActionDescriptor(
            id: FinderContextMenuActionID(
                featureID: featureID,
                localID: action.id
            ),
            title: action.title,
            icon: action.icon,
            requiredApplication: action.requiredApplication
        )
        isAvailableClosure = action.isAvailable
        performClosure = { snapshot in
            let logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "EnhancedContextMenu",
                category: "ContextCommandFeature"
            )
            logger.debug(
                "Handling Finder action \(featureID.rawValue, privacy: .public)/\(action.id.rawValue, privacy: .public)"
            )

            commandClient.send(action.command(snapshot))
        }
    }

    /// 调用具体 Action 的可用性判断。
    func isAvailable(in context: FinderContextMenuEvaluationContext) -> Bool {
        isAvailableClosure(context)
    }

    /// 构造并发送该具体 Action 的类型化命令。
    func perform(in snapshot: FinderContextSnapshot) {
        performClosure(snapshot)
    }
}

/// 隐藏一个 Feature 的具体 Command 类型，并保留其功能级身份和菜单树。
struct AnyContextMenuFeature {
    /// 配置和主应用状态页使用的功能级 descriptor。
    let descriptor: ContextCommandDescriptor

    /// 引用完整 Action descriptor 的递归菜单布局。
    let layout: [ContextMenuLayout<FinderContextMenuActionDescriptor>]

    /// 当前 Feature 的全部类型擦除 Action。
    let actions: [AnyContextMenuAction]

    /// 把 Feature 的局部 Action 身份扩展为全局复合身份。
    init<Feature: ContextMenuFeature>(_ feature: Feature) {
        let featureDescriptor = Feature.Command.descriptor
        let featureMenu = feature.menu
        let erasedActions = featureMenu.actions.map {
            AnyContextMenuAction(
                $0,
                featureID: featureDescriptor.id,
                commandClient: feature.commandClient
            )
        }
        let descriptorsByLocalID = Dictionary(
            uniqueKeysWithValues: erasedActions.map {
                ($0.descriptor.id.localID, $0.descriptor)
            }
        )

        descriptor = featureDescriptor
        layout = Self.eraseLayout(
            featureMenu.layout,
            descriptorsByLocalID: descriptorsByLocalID
        )
        actions = erasedActions
    }

    /// 递归把局部布局引用替换为可直接渲染的完整 Action descriptor。
    private static func eraseLayout(
        _ layout: [ContextMenuLayout<ContextMenuActionLocalID>],
        descriptorsByLocalID: [
            ContextMenuActionLocalID: FinderContextMenuActionDescriptor
        ]
    ) -> [ContextMenuLayout<FinderContextMenuActionDescriptor>] {
        layout.map { node in
            switch node {
            case .item(let localID):
                guard let descriptor = descriptorsByLocalID[localID] else {
                    preconditionFailure("A Finder menu layout referenced an unknown Action")
                }
                return .item(descriptor)
            case .separator:
                return .separator
            case .submenu(let title, let children):
                return .submenu(
                    title: title,
                    children: eraseLayout(
                        children,
                        descriptorsByLocalID: descriptorsByLocalID
                    )
                )
            }
        }
    }
}

/// Finder 菜单 result builder 拼接布局和 Feature 时使用的中间值。
struct FinderContextMenuComponent {
    /// 当前声明片段产生的递归菜单节点。
    let layout: [ContextMenuLayout<FinderContextMenuActionDescriptor>]

    /// 当前声明片段按产品顺序注册的具体 Feature。
    let features: [AnyContextMenuFeature]
}

/// 同时保存 Finder 布局、功能目录和具体 Action 的不可变产品声明。
struct FinderContextMenuDefinition {
    /// 保留 Finder 展示顺序和层级的递归布局。
    let layout: [ContextMenuLayout<FinderContextMenuActionDescriptor>]

    /// 按 Finder 产品顺序排列、每个 Feature 只出现一次的命令目录项。
    let items: [ContextCommandDescriptor]

    /// 按复合身份索引的具体 Finder Action 注册表。
    let actions: [FinderContextMenuActionID: AnyContextMenuAction]

    /// 使用一棵声明树同时构造布局、功能目录和 Action 注册表。
    init(
        @FinderContextMenuBuilder content: () -> FinderContextMenuComponent
    ) {
        let component = content()
        let descriptors = component.features.map(\.descriptor)
        let featureIDs = descriptors.map(\.id)
        precondition(
            Set(featureIDs).count == featureIDs.count,
            "A Finder context-menu Feature was registered more than once"
        )

        let registeredActions = component.features.flatMap(\.actions)
        let actionIDs = registeredActions.map(\.descriptor.id)
        precondition(
            Set(actionIDs).count == actionIDs.count,
            "A Finder context-menu Action was registered more than once"
        )

        layout = component.layout
        items = descriptors
        actions = Dictionary(
            uniqueKeysWithValues: registeredActions.map {
                ($0.descriptor.id, $0)
            }
        )
    }
}

/// 在 Finder 声明树中插入一条系统分隔线。
struct ContextMenuSeparator {
    /// 创建一个无状态的分隔线声明。
    init() {}
}

/// 在 Finder 产品声明树中递归组合一组完整 Feature。
struct FinderContextMenuSubmenu {
    /// 子菜单的固定产品标题。
    let title: String

    /// 子菜单内部同时生成的布局和 Feature。
    let content: FinderContextMenuComponent

    /// 使用 Finder 产品 builder 创建嵌套菜单。
    init(
        _ title: String,
        @FinderContextMenuBuilder content: () -> FinderContextMenuComponent
    ) {
        precondition(!title.isEmpty)
        self.title = title
        self.content = content()
    }
}

/// 把顺序书写的具体 Feature 直接组合为 Finder 菜单声明树。
@resultBuilder
enum FinderContextMenuBuilder {
    /// result builder 的统一中间类型。
    typealias Component = FinderContextMenuComponent

    /// 一个具体 Feature 贡献自己的完整菜单子树和运行时 Action。
    static func buildExpression<Feature: ContextMenuFeature>(
        _ expression: Feature
    ) -> Component {
        let feature = AnyContextMenuFeature(expression)
        return FinderContextMenuComponent(
            layout: feature.layout,
            features: [feature]
        )
    }

    /// 把系统分隔线加入产品布局，不注册 Feature。
    static func buildExpression(_: ContextMenuSeparator) -> Component {
        FinderContextMenuComponent(layout: [.separator], features: [])
    }

    /// 把一组完整 Feature 的子菜单递归嵌入产品布局。
    static func buildExpression(
        _ expression: FinderContextMenuSubmenu
    ) -> Component {
        FinderContextMenuComponent(
            layout: [
                .submenu(
                    title: expression.title,
                    children: expression.content.layout
                ),
            ],
            features: expression.content.features
        )
    }

    /// 按书写顺序拼接同级布局和 Feature。
    static func buildBlock(_ components: Component...) -> Component {
        FinderContextMenuComponent(
            layout: components.flatMap(\.layout),
            features: components.flatMap(\.features)
        )
    }

    /// 支持根据产品编译条件省略一段声明。
    static func buildOptional(_ component: Component?) -> Component {
        component ?? FinderContextMenuComponent(layout: [], features: [])
    }

    /// 支持声明中的第一个条件分支。
    static func buildEither(first component: Component) -> Component {
        component
    }

    /// 支持声明中的第二个条件分支。
    static func buildEither(second component: Component) -> Component {
        component
    }

    /// 支持以循环生成同级 Feature。
    static func buildArray(_ components: [Component]) -> Component {
        FinderContextMenuComponent(
            layout: components.flatMap(\.layout),
            features: components.flatMap(\.features)
        )
    }
}

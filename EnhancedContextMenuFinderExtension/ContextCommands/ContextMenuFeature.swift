import Foundation
import FinderSync
import OSLog

/// Finder 触发右键菜单时的框架上下文种类。
nonisolated enum FinderMenuContext: Sendable {
    /// 在目录内容区域的空白位置打开菜单。
    case container

    /// 在一个或多个选中项目上打开菜单。
    case items

    /// 在 Finder 侧边栏项目上打开菜单。
    case sidebar
}

/// Finder 请求菜单时已经解释完成、只在 Extension 内存活的语义快照。
nonisolated enum FinderContextSnapshot: Equatable, Sendable {
    /// 对当前可见目录本身执行空白区域命令。
    case container(path: AbsoluteFilePath)

    /// 对一个经过验证的非空 Finder 选择集合执行项目命令。
    case items(selection: FinderItemSelection)

    /// 对侧边栏所代表的目录执行命令。
    case sidebar(path: AbsoluteFilePath)

    /// 当前语义上下文中保持 Finder 顺序的强类型绝对路径。
    var absolutePaths: [AbsoluteFilePath] {
        switch self {
        case .container(let path), .sidebar(let path):
            return [path]
        case .items(let selection):
            return selection.absolutePaths
        }
    }
}

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
            guard
                let directoryURL = selectedURLs.first ?? targetedURL,
                let path = AbsoluteFilePath(url: directoryURL)
            else {
                return nil
            }
            return .container(path: path)

        case .items:
            guard let selection = FinderItemSelection(urls: selectedURLs) else {
                return nil
            }
            return .items(selection: selection)

        case .sidebar:
            guard
                let directoryURL = targetedURL,
                let path = AbsoluteFilePath(url: directoryURL)
            else {
                return nil
            }
            return .sidebar(path: path)
        }
    }
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

/// 可以声明 Finder 菜单树并构造类型化命令的增量功能。
protocol ContextMenuFeature: AnyObject {
    /// 当前 Feature 所有 Action 共用的跨进程命令类型。
    associatedtype Command: ContextCommandPayload

    /// 向主应用投递当前功能命令的客户端。
    var commandClient: ContextCommandClient { get }

    /// 当前 Feature 独立拥有的叶子、分隔线和子菜单。
    var nodes: [ContextMenuNode<ContextMenuAction<Command>>] { get }
}

/// 只有一个菜单 Action 的 Feature 使用的简洁协议。
/// 返回 `nil` 同时表示当前上下文不显示该命令。
protocol SingleActionContextMenuFeature: ContextMenuFeature {
    /// 在本次菜单上下文中准备可执行命令。
    func command(
        in context: FinderContextMenuEvaluationContext
    ) -> Command?
}

extension SingleActionContextMenuFeature {
    /// 从共享 descriptor 自动生成单一叶子。
    var nodes: [ContextMenuNode<ContextMenuAction<Command>>] {
        let descriptor = Command.descriptor
        return [
            .item(
                ContextMenuAction(
                    id: "primary",
                    title: descriptor.title,
                    icon: descriptor.icon,
                    command: { [self] context in
                        command(in: context)
                    }
                )
            ),
        ]
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
}

/// 一个 Feature 内声明的类型化菜单叶子。
struct ContextMenuAction<Command: ContextCommandPayload> {
    /// Feature 内唯一的局部身份。
    let id: ContextMenuActionLocalID

    /// 菜单叶子的产品名称。
    let title: String

    /// 菜单叶子的图标来源。
    let icon: ContextCommandIcon

    /// 构造可执行命令；当前上下文不可用时返回 `nil`。
    let command: (FinderContextMenuEvaluationContext) -> Command?

    /// 声明一个类型化菜单 Action。
    /// - Parameters:
    ///   - id: Feature 内保持稳定且唯一的局部标识。
    ///   - title: Finder 显示的叶子名称。
    ///   - icon: Finder 显示的图标来源。
    ///   - command: 从本次求值上下文创建类型化命令。
    init(
        id: String,
        title: String,
        icon: ContextCommandIcon,
        command: @escaping (FinderContextMenuEvaluationContext) -> Command?
    ) {
        precondition(!title.isEmpty)
        switch icon {
        case .systemSymbol(let name):
            precondition(!name.isEmpty)
        case .application:
            break
        }

        self.id = ContextMenuActionLocalID(rawValue: id)
        self.title = title
        self.icon = icon
        self.command = command
    }
}

/// 菜单构建时已经冻结参数、可以直接调用的 Action。
final class PreparedContextMenuAction {
    /// Finder 渲染叶子所需的产品信息。
    let descriptor: FinderContextMenuActionDescriptor

    /// 已经捕获类型化 Command 的单次投递行为。
    private let performClosure: () -> Void

    /// 绑定展示信息和准备好的调用。
    init(
        descriptor: FinderContextMenuActionDescriptor,
        perform: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        performClosure = perform
    }

    /// 投递菜单构建时已经准备好的命令。
    func perform() {
        performClosure()
    }
}

/// 隐藏具体 Command 类型，供产品菜单树统一存储叶子。
final class AnyContextMenuAction {
    /// 菜单 Action 日志共用的稳定分类。
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EnhancedContextMenu",
        category: "ContextCommandFeature"
    )

    /// 具体叶子的完整身份和展示信息。
    let descriptor: FinderContextMenuActionDescriptor

    /// 类型擦除后的命令准备行为。
    private let prepareClosure: (
        FinderContextMenuEvaluationContext
    ) -> PreparedContextMenuAction?

    /// 为一个 Feature 的具体叶子绑定共享命令类型和投递客户端。
    init<Command: ContextCommandPayload>(
        _ action: ContextMenuAction<Command>,
        featureID: ContextCommandFeatureID,
        commandClient: ContextCommandClient
    ) {
        let descriptor = FinderContextMenuActionDescriptor(
            id: FinderContextMenuActionID(
                featureID: featureID,
                localID: action.id
            ),
            title: action.title,
            icon: action.icon
        )
        self.descriptor = descriptor
        prepareClosure = { context in
            guard let command = action.command(context) else {
                return nil
            }
            return PreparedContextMenuAction(descriptor: descriptor) {
                let actionName = "\(featureID.rawValue)/\(action.id.rawValue)"
                Self.logger.debug(
                    "Handling Finder action \(actionName, privacy: .public)"
                )
                commandClient.send(command)
            }
        }
    }

    /// 在菜单构建时同时决定可见性并冻结命令。
    func prepare(
        in context: FinderContextMenuEvaluationContext
    ) -> PreparedContextMenuAction? {
        prepareClosure(context)
    }
}

/// 保存 Finder 产品顺序、层级和可执行叶子的不可变声明。
struct FinderContextMenuDefinition {
    /// 产品声明和运行时准备共用的递归菜单树。
    let nodes: [ContextMenuNode<AnyContextMenuAction>]

    /// 使用一棵声明树构造并验证产品菜单。
    init(
        @FinderContextMenuBuilder content: () -> [
            ContextMenuNode<AnyContextMenuAction>
        ]
    ) {
        let nodes = content()
        let actionIDs = nodes
            .flatMap { $0.items }
            .map(\.descriptor.id)
        precondition(
            Set(actionIDs).count == actionIDs.count,
            "A Finder context-menu Action was registered more than once"
        )
        self.nodes = nodes
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

    /// 子菜单内部的递归节点。
    let nodes: [ContextMenuNode<AnyContextMenuAction>]

    /// 使用 Finder 产品 builder 创建嵌套菜单。
    init(
        _ title: String,
        @FinderContextMenuBuilder content: () -> [
            ContextMenuNode<AnyContextMenuAction>
        ]
    ) {
        precondition(!title.isEmpty)
        self.title = title
        nodes = content()
    }
}

/// 把顺序书写的具体 Feature 直接组合为 Finder 菜单声明树。
@resultBuilder
enum FinderContextMenuBuilder {
    /// result builder 的统一中间类型。
    typealias Component = [ContextMenuNode<AnyContextMenuAction>]

    /// 一个具体 Feature 贡献自己的完整菜单子树和运行时 Action。
    static func buildExpression<Feature: ContextMenuFeature>(
        _ expression: Feature
    ) -> Component {
        let featureID = Feature.Command.descriptor.id
        let nodes = expression.nodes.map { node in
            node.mapItems { action in
                AnyContextMenuAction(
                    action,
                    featureID: featureID,
                    commandClient: expression.commandClient
                )
            }
        }
        precondition(
            !nodes.flatMap({ $0.items }).isEmpty,
            "A Finder context-menu Feature must declare at least one Action"
        )
        return nodes
    }

    /// 把系统分隔线加入产品布局，不注册 Feature。
    static func buildExpression(_: ContextMenuSeparator) -> Component {
        [.separator]
    }

    /// 把一组完整 Feature 的子菜单递归嵌入产品布局。
    static func buildExpression(
        _ expression: FinderContextMenuSubmenu
    ) -> Component {
        [.submenu(title: expression.title, children: expression.nodes)]
    }

    /// 按书写顺序拼接同级布局和 Feature。
    static func buildBlock(_ components: Component...) -> Component {
        components.flatMap { $0 }
    }
}

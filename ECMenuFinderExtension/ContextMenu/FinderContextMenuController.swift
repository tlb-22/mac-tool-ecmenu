import AppKit
import FinderSync

/// 解释声明式布局、渲染 Finder 菜单并把 action 路由到增量功能。
final class FinderContextMenuController {
    /// Finder 菜单图标使用的系统菜单字体。
    private static let menuIconFont = NSFont.menuFont(ofSize: 0)

    /// SF Symbol 相对菜单字体使用的统一系统比例。
    private static let systemSymbolScale: NSImage.SymbolScale = .small

    /// 菜单字体完整行盒向上取整后的正方形画布边长。
    ///
    /// Finder host 会把非正方形 `NSImage` 拉伸到方形槽位，因此所有来源
    /// 都必须先在 Extension 内保持比例地包装为正方形图像。
    private static let menuIconCanvasLength = ceil(
        menuIconFont.ascender
            - menuIconFont.descender
            + menuIconFont.leading
    )

    /// SF Symbol 和应用图标共用的正方形画布。
    private static let menuIconCanvasSize = NSSize(
        width: menuIconCanvasLength,
        height: menuIconCanvasLength
    )

    /// 跨连续菜单请求保留的最近 action 数量，避免未点击菜单无限积累。
    private static let maximumRetainedActions = 256

    /// 由 Finder Extension 拥有的菜单顺序、分组和层级声明。
    private let menu: FinderContextMenuDefinition

    /// 查询产品当前是否应向 Finder 贡献任何右键菜单的纯边界。
    private let isMenuEnabled: () -> Bool

    /// 查询一个功能当前是否被产品配置显示的纯边界。
    private let isFeatureVisible: (ContextCommandFeatureID) -> Bool

    /// 查询 Launch Services 当前能否定位声明的固定应用。
    private let isApplicationAvailable: (
        ContextCommandApplicationRequirement
    ) -> Bool

    /// 各菜单实例唯一 action tag 对应的已准备调用。
    private var preparedActionsByTag: [Int: PreparedContextMenuAction] = [:]

    /// 按注册顺序保存尚未执行的 action tag，供有界淘汰使用。
    private var retainedActionTags: [Int] = []

    /// 下一个分配给具体菜单项的正整数 tag。
    private var nextActionTag = 1

    /// 复用已经居中适配的固定符号和应用图标，避免重复创建图像。
    private var iconCache: [String: NSImage] = [:]

    /// 使用菜单声明树和纯配置查询创建稳定运行时。
    /// - Parameters:
    ///   - menu: 产品声明的菜单项、顺序、分组和层级。
    ///   - isFeatureVisible: 查询一个功能是否应出现在 Finder 菜单中。
    ///   - isMenuEnabled: 查询产品总开关是否允许贡献右键菜单。
    ///   - isApplicationAvailable: 查询一个固定应用依赖是否可用。
    init(
        menu: FinderContextMenuDefinition,
        isFeatureVisible: @escaping (ContextCommandFeatureID) -> Bool,
        isMenuEnabled: @escaping () -> Bool = { true },
        isApplicationAvailable: @escaping (
            ContextCommandApplicationRequirement
        ) -> Bool = { requirement in
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: requirement.bundleIdentifier
            ) != nil
        }
    ) {
        self.menu = menu
        self.isFeatureVisible = isFeatureVisible
        self.isMenuEnabled = isMenuEnabled
        self.isApplicationAvailable = isApplicationAvailable
    }

    /// 把 Extension 配置副本适配为 Controller 使用的纯查询边界。
    /// - Parameters:
    ///   - menu: 产品声明的菜单项、顺序、分组和层级。
    ///   - configuration: Extension 持有的可见性配置副本。
    convenience init(
        menu: FinderContextMenuDefinition,
        configuration: MenuConfigurationReplica
    ) {
        self.init(
            menu: menu,
            isFeatureVisible: { [configuration] featureID in
                configuration.isVisible(featureID)
            },
            isMenuEnabled: { [configuration] in
                configuration.isEnabled
            }
        )
    }

    // MARK: - ==================== 副作用：渲染声明式菜单 ====================

    /// 把当前 Finder 上下文中的可见布局解释为 `NSMenu`。
    /// - Parameters:
    ///   - menuKind: Finder 原始菜单类型。
    ///   - action: `FinderSync` 主对象公开的通用 action。
    /// - Returns: 至少包含一个动作项时返回菜单，否则返回 `nil`。
    func menu(for menuKind: FIMenuKind, action: Selector) -> NSMenu? {
        guard isMenuEnabled() else {
            return nil
        }
        guard
            let context = FinderMenuContext(menuKind),
            let snapshot = FinderContextReader.snapshot(for: context)
        else {
            return nil
        }
        return menu(for: snapshot, action: action)
    }

    /// 使用 Finder 请求菜单时已经冻结的状态渲染菜单。
    ///
    /// 菜单可用性和随后发生的 action 共用这份值，避免 action 回调时
    /// Finder 的瞬时选择状态已经发生变化。
    /// - Parameters:
    ///   - snapshot: 当前菜单实例唯一对应的 Finder 快照。
    ///   - action: `FinderSync` 主对象公开的通用 action。
    /// - Returns: 至少包含一个动作项时返回菜单，否则返回 `nil`。
    func menu(
        for snapshot: FinderContextSnapshot,
        action: Selector
    ) -> NSMenu? {
        guard isMenuEnabled() else {
            return nil
        }
        let evaluationContext = FinderContextMenuEvaluationContext(
            snapshot: snapshot
        )
        let nodes: [ContextMenuNode<PreparedContextMenuAction>] =
            ContextMenuNodeResolver.compactMapItems(
                in: menu.nodes
            ) { [isFeatureVisible, isApplicationAvailable] action in
                let descriptor = action.descriptor
                guard isFeatureVisible(descriptor.id.featureID) else {
                    return nil
                }
                guard descriptor.icon.applicationRequirement.map(
                    isApplicationAvailable
                ) ?? true else {
                    return nil
                }
                return action.prepare(in: evaluationContext)
            }
        guard !nodes.isEmpty else {
            return nil
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        nodes.forEach {
            menu.addItem(
                menuItem(
                    from: $0,
                    action: action
                )
            )
        }
        return menu
    }

    /// 递归把一个已经过滤和规范化的布局节点渲染为 AppKit 菜单项。
    private func menuItem(
        from node: ContextMenuNode<PreparedContextMenuAction>,
        action: Selector
    ) -> NSMenuItem {
        switch node {
        case .item(let preparedAction):
            let descriptor = preparedAction.descriptor
            let menuItem = NSMenuItem(
                title: descriptor.title,
                action: action,
                keyEquivalent: ""
            )
            menuItem.isEnabled = true
            menuItem.tag = retain(preparedAction)
            menuItem.image = menuIcon(for: descriptor)
            return menuItem

        case .separator:
            return .separator()

        case .submenu(let title, let children):
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            children.forEach {
                submenu.addItem(
                    menuItem(from: $0, action: action)
                )
            }
            parent.submenu = submenu
            return parent
        }
    }

    /// 把共享的无框架图标声明解析为 Finder 可以显示的 AppKit 图像。
    /// - Parameter descriptor: 当前具体 Action 的产品描述。
    /// - Returns: SF Symbol、实际应用图标或图标读取失败占位符。
    private func menuIcon(
        for descriptor: FinderContextMenuActionDescriptor
    ) -> NSImage? {
        switch descriptor.icon {
        case .systemSymbol(let name):
            return systemSymbol(named: name)

        case .application(let requirement):
            guard
                let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: requirement.bundleIdentifier
                )
            else {
                return systemSymbol(named: "questionmark.app.dashed")
            }

            let cacheKey = "application:\(applicationURL.path)"
            if let cachedIcon = iconCache[cacheKey] {
                return cachedIcon
            }

            let sourceIcon = NSWorkspace.shared.icon(
                forFile: applicationURL.path
            )
            guard let icon = AppKitIconCanvasRenderer
                .proportionallyFittedImage(
                    sourceIcon,
                    canvasSize: Self.menuIconCanvasSize
                )
            else {
                return systemSymbol(named: "questionmark.app.dashed")
            }
            iconCache[cacheKey] = icon
            return icon
        }
    }

    /// 创建不会被 Finder 非等比拉伸的 SF Symbol，并按名称缓存。
    /// - Parameter name: SF Symbols 中的稳定符号名称。
    /// - Returns: 当前系统支持该符号时返回保持自然比例和语义对齐的图像。
    private func systemSymbol(named name: String) -> NSImage? {
        let cacheKey = "symbol:\(name)"
        if let cachedIcon = iconCache[cacheKey] {
            return cachedIcon
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: Self.menuIconFont.pointSize,
            weight: .regular,
            scale: Self.systemSymbolScale
        ).applying(
            NSImage.SymbolConfiguration(hierarchicalColor: .labelColor)
        )
        guard let sourceIcon = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration),
            let icon = AppKitIconCanvasRenderer.semanticCenteredSymbol(
                sourceIcon,
                canvasSize: Self.menuIconCanvasSize
            )
        else {
            return nil
        }

        iconCache[cacheKey] = icon
        return icon
    }

    // MARK: - ==================== 副作用：路由 Finder 动作 ====================

    /// 取出菜单项 tag 已经绑定的命令并直接投递。
    /// - Parameter menuItem: Finder 回传的菜单项。
    func perform(_ menuItem: NSMenuItem) {
        guard menuItem.isEnabled, menuItem.action != nil else {
            return
        }

        guard let preparedAction = consumePreparedAction(for: menuItem) else {
            NSSound.beep()
            return
        }

        preparedAction.perform()
    }

    /// 为一个具体菜单项分配唯一 tag，并保留已准备调用。
    ///
    /// Finder 可能在旧菜单 action 到达前请求另一种菜单。固定 Action tag
    /// 会让后一次请求覆盖前一个菜单的快照，因此 tag 必须属于菜单项实例。
    /// - Parameter preparedAction: 菜单构建时已经冻结的调用。
    /// - Returns: Finder 可以原样回传的正整数 tag。
    private func retain(_ preparedAction: PreparedContextMenuAction) -> Int {
        let tag = nextActionTag
        nextActionTag = tag == Int.max ? 1 : tag + 1

        precondition(
            preparedActionsByTag[tag] == nil,
            "Finder action tag wrapped into a retained action"
        )
        preparedActionsByTag[tag] = preparedAction
        retainedActionTags.append(tag)

        while retainedActionTags.count > Self.maximumRetainedActions {
            let expiredTag = retainedActionTags.removeFirst()
            preparedActionsByTag.removeValue(forKey: expiredTag)
        }
        return tag
    }

    /// 取出本次 action 的已准备调用，并释放路由记录。
    /// - Parameter menuItem: Finder 回传的具体菜单项。
    /// - Returns: 该菜单项构建时绑定的 Action；tag 无效时为 `nil`。
    private func consumePreparedAction(
        for menuItem: NSMenuItem
    ) -> PreparedContextMenuAction? {
        let tag = menuItem.tag
        guard let action = preparedActionsByTag.removeValue(forKey: tag) else {
            return nil
        }
        retainedActionTags.removeAll { $0 == tag }
        return action
    }

    /// 从 Finder 原样回传的唯一菜单项 tag 查询已准备调用。
    /// - Parameter menuItem: Finder 回传的菜单项。
    /// - Returns: 当前菜单构建时注册的 Action；tag 无效时为 `nil`。
    func preparedAction(
        for menuItem: NSMenuItem
    ) -> PreparedContextMenuAction? {
        preparedActionsByTag[menuItem.tag]
    }
}

// MARK: - ==================== 纯函数：Finder 上下文映射 ====================

/// 定义 Finder 框架菜单类型到共享语义上下文的边界映射。
private extension FinderMenuContext {
    /// 把 Finder 框架菜单类型映射为跨进程共享的上下文类型。
    /// - Parameter menuKind: Finder 原始菜单类型。
    init?(_ menuKind: FIMenuKind) {
        switch menuKind {
        case .contextualMenuForContainer:
            self = .container
        case .contextualMenuForItems:
            self = .items
        case .contextualMenuForSidebar:
            self = .sidebar
        default:
            return nil
        }
    }
}

import AppKit
import FinderSync

/// 把一次菜单构建时冻结的 Finder 语义绑定到对应 action tag。
struct FinderContextMenuActionContext {
    /// 需要执行的具体 Feature Action。
    let actionID: FinderContextMenuActionID

    /// Finder 请求该菜单时同步冻结的确定语义。
    let snapshot: FinderContextSnapshot

    /// 创建一份只属于单个菜单项的不可变 action 上下文。
    init(
        actionID: FinderContextMenuActionID,
        snapshot: FinderContextSnapshot
    ) {
        self.actionID = actionID
        self.snapshot = snapshot
    }
}

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
    private static let maximumRetainedActionContexts = 256

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

    /// 按复合身份索引的具体菜单 Action 注册表。
    private let actions: [FinderContextMenuActionID: AnyContextMenuAction]

    /// 各菜单实例唯一 action tag 对应的具体 Action 和构建快照。
    private var actionContextsByTag: [Int: FinderContextMenuActionContext] = [:]

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
        actions = menu.actions
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
        let elements = ContextMenuLayoutResolver.visibleElements(
            in: menu.layout,
            isItemVisible: {
                [isFeatureVisible, isApplicationAvailable, actions] item in
                isFeatureVisible(item.id.featureID)
                    && (item.requiredApplication.map(
                        isApplicationAvailable
                    ) ?? true)
                    && actions[item.id]?.isAvailable(in: evaluationContext) == true
            }
        )
        guard !elements.isEmpty else {
            return nil
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        elements.forEach {
            menu.addItem(
                menuItem(
                    from: $0,
                    context: evaluationContext,
                    action: action
                )
            )
        }
        return menu
    }

    /// 递归把一个已经过滤和规范化的布局节点渲染为 AppKit 菜单项。
    private func menuItem(
        from element: ContextMenuVisibleElement<FinderContextMenuActionDescriptor>,
        context: FinderContextMenuEvaluationContext,
        action: Selector
    ) -> NSMenuItem {
        switch element {
        case .item(let definition):
            let menuItem = NSMenuItem(
                title: definition.title,
                action: action,
                keyEquivalent: ""
            )
            menuItem.isEnabled = true
            menuItem.tag = retainActionContext(
                FinderContextMenuActionContext(
                    actionID: definition.id,
                    snapshot: context.snapshot
                )
            )
            menuItem.image = menuIcon(for: definition)
            return menuItem

        case .separator:
            return .separator()

        case .submenu(let title, let children):
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            children.forEach {
                submenu.addItem(
                    menuItem(from: $0, context: context, action: action)
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

        case .requiredApplication:
            guard
                let requirement = descriptor.requiredApplication,
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

    /// 读取菜单项 tag 对应的构建快照，并交给对应的具体 Action。
    /// - Parameter menuItem: Finder 回传的菜单项。
    func perform(_ menuItem: NSMenuItem) {
        guard menuItem.isEnabled, menuItem.action != nil else {
            return
        }

        guard
            let actionContext = consumeActionContext(for: menuItem),
            let action = actions[actionContext.actionID]
        else {
            NSSound.beep()
            return
        }

        action.perform(in: actionContext.snapshot)
    }

    /// 为一个具体菜单项分配唯一 tag，并跨后续菜单请求保留其上下文。
    ///
    /// Finder 可能在旧菜单 action 到达前请求另一种菜单。固定 Action tag
    /// 会让后一次请求覆盖前一个菜单的快照，因此 tag 必须属于菜单项实例。
    /// - Parameter actionContext: 具体 Action 身份及其菜单构建快照。
    /// - Returns: Finder 可以原样回传的正整数 tag。
    private func retainActionContext(
        _ actionContext: FinderContextMenuActionContext
    ) -> Int {
        let tag = nextActionTag
        nextActionTag = tag == Int.max ? 1 : tag + 1

        precondition(
            actionContextsByTag[tag] == nil,
            "Finder action tag wrapped into a retained context"
        )
        actionContextsByTag[tag] = actionContext
        retainedActionTags.append(tag)

        while retainedActionTags.count > Self.maximumRetainedActionContexts {
            let expiredTag = retainedActionTags.removeFirst()
            actionContextsByTag.removeValue(forKey: expiredTag)
        }
        return tag
    }

    /// 取出本次 action 的不可变上下文，并释放已经关闭菜单的路由记录。
    /// - Parameter menuItem: Finder 回传的具体菜单项。
    /// - Returns: 该菜单项构建时绑定的 Action 和快照；tag 无效时为 `nil`。
    private func consumeActionContext(
        for menuItem: NSMenuItem
    ) -> FinderContextMenuActionContext? {
        let tag = menuItem.tag
        guard let actionContext = actionContextsByTag.removeValue(forKey: tag) else {
            return nil
        }
        retainedActionTags.removeAll { $0 == tag }
        return actionContext
    }

    /// 从 Finder 原样回传的唯一菜单项 tag 恢复 action 上下文。
    /// - Parameter menuItem: Finder 回传的菜单项。
    /// - Returns: 当前菜单构建时注册的 Action 和快照；tag 无效时为 `nil`。
    func actionContext(
        for menuItem: NSMenuItem
    ) -> FinderContextMenuActionContext? {
        actionContextsByTag[menuItem.tag]
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

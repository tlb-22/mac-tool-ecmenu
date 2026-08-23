/// 声明 Finder 右键菜单中可递归组合的通用布局节点。
nonisolated indirect enum ContextMenuLayout<Item>: Equatable, Sendable
where Item: Equatable & Sendable {
    /// 引用一个增量菜单项，由运行时注册表解析其可用性和动作。
    case item(Item)

    /// 在同级可见项目之间显示系统分隔线。
    case separator

    /// 使用固定产品标题折叠一组子节点。
    case submenu(title: String, children: [ContextMenuLayout<Item>])
}

/// 表示经过可见性过滤、可以直接渲染的 Finder 菜单节点。
nonisolated indirect enum ContextMenuVisibleElement<Item>: Equatable, Sendable
where Item: Equatable & Sendable {
    /// 当前 Finder 上下文中可见的菜单项。
    case item(Item)

    /// 已规范化的同级分隔线。
    case separator

    /// 至少包含一个可见后代的子菜单。
    case submenu(
        title: String,
        children: [ContextMenuVisibleElement<Item>]
    )
}

/// 把声明式 Finder 菜单树解析为可直接渲染的规范化节点。
enum ContextMenuLayoutResolver {
    /// 根据菜单项可见性递归过滤布局，并删除无效分隔线和空子菜单。
    /// - Parameters:
    ///   - layout: 未经 Finder 上下文过滤的声明式布局。
    ///   - isItemVisible: 查询一个功能菜单项当前是否可见的纯回调。
    /// - Returns: 可以直接渲染的规范化节点序列。
    nonisolated static func visibleElements<Item>(
        in layout: [ContextMenuLayout<Item>],
        isItemVisible: (Item) -> Bool
    ) -> [ContextMenuVisibleElement<Item>]
    where Item: Equatable & Sendable {
        let mapped: [ContextMenuVisibleElement<Item>?] = layout.map { node in
            switch node {
            case .item(let item):
                return isItemVisible(item) ? .item(item) : nil

            case .separator:
                return .separator

            case .submenu(let title, let children):
                let visibleChildren = visibleElements(
                    in: children,
                    isItemVisible: isItemVisible
                )
                return visibleChildren.isEmpty
                    ? nil
                    : .submenu(title: title, children: visibleChildren)
            }
        }

        return normalizedSeparators(in: mapped.compactMap { $0 })
    }

    /// 删除开头、结尾和连续的分隔线。
    private nonisolated static func normalizedSeparators<Item>(
        in elements: [ContextMenuVisibleElement<Item>]
    ) -> [ContextMenuVisibleElement<Item>]
    where Item: Equatable & Sendable {
        var result: [ContextMenuVisibleElement<Item>] = []

        for element in elements {
            if case .separator = element {
                guard !result.isEmpty else {
                    continue
                }
                guard case .separator? = result.last else {
                    result.append(element)
                    continue
                }
            } else {
                result.append(element)
            }
        }

        if case .separator? = result.last {
            result.removeLast()
        }
        return result
    }
}

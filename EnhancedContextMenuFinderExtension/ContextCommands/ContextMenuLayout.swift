/// Finder 右键菜单在声明、准备和渲染阶段共用的递归节点。
nonisolated indirect enum ContextMenuNode<Item> {
    /// 当前阶段携带的一个菜单叶子。
    case item(Item)

    /// 在同级有效项目之间显示系统分隔线。
    case separator

    /// 使用固定产品标题折叠一组子节点。
    case submenu(title: String, children: [ContextMenuNode<Item>])

    /// 按菜单顺序递归展开所有叶子。
    var items: [Item] {
        switch self {
        case .item(let item):
            return [item]
        case .separator:
            return []
        case .submenu(_, let children):
            return children.flatMap { $0.items }
        }
    }

    /// 只替换叶子值，保留原始层级和分隔线。
    func mapItems<MappedItem>(
        _ transform: (Item) -> MappedItem
    ) -> ContextMenuNode<MappedItem> {
        switch self {
        case .item(let item):
            return .item(transform(item))
        case .separator:
            return .separator
        case .submenu(let title, let children):
            return .submenu(
                title: title,
                children: children.map { $0.mapItems(transform) }
            )
        }
    }
}

extension ContextMenuNode: Equatable where Item: Equatable {}
extension ContextMenuNode: Sendable where Item: Sendable {}

/// 在不改变菜单节点类型的前提下准备并规范化递归树。
enum ContextMenuNodeResolver {
    /// 递归转换可保留的叶子，删除空子菜单和无效分隔线。
    /// - Parameters:
    ///   - nodes: 当前阶段的菜单节点。
    ///   - transform: 返回下一阶段叶子，或以 `nil` 过滤当前叶子。
    /// - Returns: 保留原始顺序与层级的规范化节点。
    nonisolated static func compactMapItems<Item, MappedItem>(
        in nodes: [ContextMenuNode<Item>],
        _ transform: (Item) -> MappedItem?
    ) -> [ContextMenuNode<MappedItem>] {
        let mapped = nodes.compactMap { node -> ContextMenuNode<MappedItem>? in
            switch node {
            case .item(let item):
                return transform(item).map(ContextMenuNode<MappedItem>.item)

            case .separator:
                return .separator

            case .submenu(let title, let children):
                let mappedChildren = compactMapItems(
                    in: children,
                    transform
                )
                return mappedChildren.isEmpty
                    ? nil
                    : .submenu(title: title, children: mappedChildren)
            }
        }

        return normalizedSeparators(in: mapped)
    }

    /// 删除开头、结尾和连续的分隔线。
    private nonisolated static func normalizedSeparators<Item>(
        in nodes: [ContextMenuNode<Item>]
    ) -> [ContextMenuNode<Item>] {
        var result: [ContextMenuNode<Item>] = []

        for node in nodes {
            if case .separator = node {
                guard !result.isEmpty else {
                    continue
                }
                guard case .separator? = result.last else {
                    result.append(node)
                    continue
                }
            } else {
                result.append(node)
            }
        }

        if case .separator? = result.last {
            result.removeLast()
        }
        return result
    }
}

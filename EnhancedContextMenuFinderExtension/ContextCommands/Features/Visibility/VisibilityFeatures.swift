import Foundation

// MARK: - ==================== 选中项目的菜单事实 ====================

/// 菜单构建阶段从单个 Finder 选中项读取的最小事实。
nonisolated struct VisibilityMenuItemFacts: Equatable, Sendable {
    /// 保留原始文件名，用于把点号名称排除出菜单状态判断。
    let name: String

    /// 普通名称对象的隐藏属性；读取失败或系统未提供时为 `nil`。
    let isHidden: Bool?
}

/// 纯函数汇总后、足以决定两个可见性菜单项是否出现的事实。
nonisolated struct VisibilitySelectionMenuFacts: Equatable, Sendable {
    /// 选择中是否至少有一个当前可见的普通名称对象。
    let hasVisibleOrdinaryItem: Bool

    /// 选择中是否至少有一个当前隐藏的普通名称对象。
    let hasHiddenOrdinaryItem: Bool

    // MARK: - ==================== 纯函数：汇总已读取事实 ====================

    /// 排除点号名称和未知状态，汇总普通对象的已知隐藏状态。
    /// - Parameter items: 保持 Finder 选择顺序的单项事实序列。
    init<Items: Sequence>(items: Items)
    where Items.Element == VisibilityMenuItemFacts {
        var hasVisibleOrdinaryItem = false
        var hasHiddenOrdinaryItem = false

        for item in items where !item.name.hasPrefix(".") {
            switch item.isHidden {
            case false:
                hasVisibleOrdinaryItem = true
            case true:
                hasHiddenOrdinaryItem = true
            case nil:
                continue
            }

            guard !(hasVisibleOrdinaryItem && hasHiddenOrdinaryItem) else {
                break
            }
        }

        self.hasVisibleOrdinaryItem = hasVisibleOrdinaryItem
        self.hasHiddenOrdinaryItem = hasHiddenOrdinaryItem
    }

    // MARK: - ==================== 副作用：读取 Finder 文件事实 ====================

    /// 只读取普通名称对象的 `isHidden` 资源值，不预检权限或可写性。
    /// - Parameter selection: Finder 菜单构建时冻结的非空选择。
    /// - Returns: 读取失败的对象保持未知，不促成任何命令出现。
    static func read(
        from selection: FinderItemSelection
    ) -> VisibilitySelectionMenuFacts {
        let items = selection.urls.lazy.map { url in
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else {
                return VisibilityMenuItemFacts(name: name, isHidden: nil)
            }

            let isHidden: Bool?
            do {
                isHidden = try url.resourceValues(
                    forKeys: [.isHiddenKey]
                ).isHidden
            } catch {
                isHidden = nil
            }
            return VisibilityMenuItemFacts(name: name, isHidden: isHidden)
        }

        return VisibilitySelectionMenuFacts(items: items)
    }
}

// MARK: - ==================== 隐藏项目 Feature ====================

/// 隐藏功能在 Finder Extension 中的可用性与命令发送端。
final class HideItemsFeature: SingleActionContextMenuFeature {
    /// 为菜单身份和跨进程负载提供唯一的共享命令类型。
    typealias Command = HideItemsCommand

    /// 向主应用投递隐藏命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 菜单构建边界读取选中项隐藏状态的函数。
    private let readSelectionFacts: (
        FinderItemSelection
    ) -> VisibilitySelectionMenuFacts

    /// 注入跨进程命令客户端与选中项事实读取边界。
    init(
        commandClient: ContextCommandClient,
        readSelectionFacts: @escaping (
            FinderItemSelection
        ) -> VisibilitySelectionMenuFacts = VisibilitySelectionMenuFacts.read
    ) {
        self.commandClient = commandClient
        self.readSelectionFacts = readSelectionFacts
    }

    /// 只为至少含一个可见普通对象的选择构造命令。
    func command(
        in context: FinderContextMenuEvaluationContext
    ) -> HideItemsCommand? {
        guard case .items(let selection) = context.snapshot else {
            return nil
        }
        let facts = context.fact(VisibilitySelectionMenuFacts.self) {
            readSelectionFacts(selection)
        }
        guard facts.hasVisibleOrdinaryItem else {
            return nil
        }
        return HideItemsCommand(selection: selection)
    }
}

// MARK: - ==================== 显示项目 Feature ====================

/// 显示功能在 Finder Extension 中的可用性与命令发送端。
final class ShowItemsFeature: SingleActionContextMenuFeature {
    /// 为菜单身份和跨进程负载提供唯一的共享命令类型。
    typealias Command = ShowItemsCommand

    /// 向主应用投递显示命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 菜单构建边界读取选中项隐藏状态的函数。
    private let readSelectionFacts: (
        FinderItemSelection
    ) -> VisibilitySelectionMenuFacts

    /// 注入跨进程命令客户端与选中项事实读取边界。
    init(
        commandClient: ContextCommandClient,
        readSelectionFacts: @escaping (
            FinderItemSelection
        ) -> VisibilitySelectionMenuFacts = VisibilitySelectionMenuFacts.read
    ) {
        self.commandClient = commandClient
        self.readSelectionFacts = readSelectionFacts
    }

    /// 只为至少含一个隐藏普通对象的选择构造命令。
    func command(
        in context: FinderContextMenuEvaluationContext
    ) -> ShowItemsCommand? {
        guard case .items(let selection) = context.snapshot else {
            return nil
        }
        let facts = context.fact(VisibilitySelectionMenuFacts.self) {
            readSelectionFacts(selection)
        }
        guard facts.hasHiddenOrdinaryItem else {
            return nil
        }
        return ShowItemsCommand(selection: selection)
    }
}

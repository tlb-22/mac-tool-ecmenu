/**
 根据同一次选择的隐藏状态汇总，分别决定隐藏与显示动作是否可用并准备相应命令。
 两个动作共享菜单求值中的事实读取，类型化选择在点击前保持不变。
 */

import Foundation

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
        ) -> VisibilitySelectionMenuFacts = VisibilityMenuFactsReader.read
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
        ) -> VisibilitySelectionMenuFacts = VisibilityMenuFactsReader.read
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

/**
 表达可见性菜单所需的单项观察，并以纯规则归纳选择中可见和隐藏的普通名称对象。
 点号名称与未知状态不促成动作出现；一旦两类状态均已确定即可结束剩余事实枚举。
 */

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
}

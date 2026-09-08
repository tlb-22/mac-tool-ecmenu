/**
 适配文件资源属性读取，把 Finder 选择逐项转换为可见性菜单事实并交给纯汇总规则。
 普通名称才读取隐藏属性，缺失值或读取失败保留为未知状态。
 */

import Foundation

/// 读取选择项隐藏属性，再交给纯规则汇总可用菜单事实。
nonisolated enum VisibilityMenuFactsReader {
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

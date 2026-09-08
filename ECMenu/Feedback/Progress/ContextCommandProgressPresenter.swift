/**
 根据运行时传入的任务快照创建、更新或释放原生进度窗口。
 持有展示窗口，并把取消与关闭操作交回注入的运行时动作。
 */

import AppKit

/// 持有当前可见的进度面板；状态与取消意图由进度中心拥有。
@MainActor
final class ContextCommandProgressPresenter {
    private var windowController: ContextCommandProgressWindowController?

    func render(_ items: [ContextCommandProgressItem], actions: ContextCommandProgressActions) {
        guard !items.isEmpty else {
            windowController?.closeWhenEmpty()
            windowController = nil
            return
        }
        if windowController == nil {
            windowController = ContextCommandProgressWindowController(
                cancelAction: actions.cancel,
                dismissAction: { [weak self] in
                    // 原生窗口正在关闭，先释放其引用，再发布隐藏意图。
                    self?.windowController = nil
                    actions.dismiss()
                }
            )
        }
        windowController?.update(with: items)
    }
}

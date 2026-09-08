/**
 集中持有已登记命令的进度、取消意图、延迟显示与隐藏状态。
 接收命令报告与用户操作，向展示层发布一致的状态快照。
 */

import Foundation

/// 唯一拥有进度事实、显示延迟与隐藏意图，通过注入边界发布可见快照。
@MainActor
final class ContextCommandProgressCenter {
    /// 快速任务不显示窗口的统一延迟。
    nonisolated static let standardDisplayDelay: Duration = .seconds(1)

    /// 测试可以替换的显示延迟；生产环境使用统一的一秒阈值。
    private let displayDelay: Duration

    /// 测试可以替换的 AppKit 渲染边界；生产环境由窗口控制器呈现。
    private let render: ([ContextCommandProgressItem], ContextCommandProgressActions) -> Void

    /// 当前仍在运行的纯进度状态。
    private var state = ContextCommandProgressState()

    /// 每个尚未显示任务对应的独立延迟任务。
    private var revealTasks: [UUID: Task<Void, Never>] = [:]

    /// 用户关闭窗口时已经可见的任务；后续新任务不继承隐藏状态。
    private var dismissedRequestIDs: Set<UUID> = []

    /// 最近一次交给渲染边界的快照，避免无可见变化时触碰 AppKit。
    private var lastRenderedItems: [ContextCommandProgressItem] = []

    /// 创建进度中心，并允许测试替换延迟和渲染副作用。
    /// - Parameters:
    ///   - displayDelay: 任务从开始到可见之间的统一阈值。
    ///   - render: 接收可见快照与交互出口的呈现边界。
    init(
        displayDelay: Duration = standardDisplayDelay,
        render: @escaping ([ContextCommandProgressItem], ContextCommandProgressActions) -> Void
    ) {
        self.displayDelay = displayDelay
        self.render = render
    }

    /// 登记任务并独立安排延迟显示。
    func begin(
        requestID: UUID,
        descriptor: ContextCommandDescriptor,
        totalUnitCount: Int
    ) {
        state.begin(
            requestID: requestID,
            descriptor: descriptor,
            totalUnitCount: totalUnitCount
        )

        let displayDelay = displayDelay
        revealTasks[requestID] = Task { [weak self] in
            do {
                try await Task.sleep(for: displayDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.reveal(requestID: requestID)
        }
    }

    /// Feature 报告一个项目已经到达终态。
    func advance(requestID: UUID) {
        state.advance(requestID: requestID)
        renderIfNeeded()
    }

    /// 返回用户在任务窗口中登记的协作取消意图。
    func isCancellationRequested(for requestID: UUID) -> Bool {
        state.isCancellationRequested(for: requestID)
    }

    /// 命令完成、失败或被 Router 取消后清理任务与延迟。
    func finish(requestID: UUID) {
        revealTasks.removeValue(forKey: requestID)?.cancel()
        state.finish(requestID: requestID)
        dismissedRequestIDs.remove(requestID)
        renderIfNeeded()
    }

    /// 延迟到期且任务仍在执行时使其进入共享窗口。
    private func reveal(requestID: UUID) {
        revealTasks[requestID] = nil
        state.reveal(requestID: requestID)
        renderIfNeeded()
    }

    /// 从窗口接收取消按钮动作，不直接取消 Router 的结构化 Task。
    func requestCancellation(requestID: UUID) {
        state.requestCancellation(requestID: requestID)
        renderIfNeeded()
    }

    /// 用户关闭窗口时只隐藏当时呈现的任务，后来任务仍可重新显示。
    func dismissVisibleItems() {
        let requestIDs = currentlyPresentedItems.map(\.requestID)
        guard !requestIDs.isEmpty else {
            return
        }

        dismissedRequestIDs.formUnion(requestIDs)

        renderIfNeeded()
    }

    /// 排除用户已经主动隐藏、但仍在后台运行的任务。
    private var currentlyPresentedItems: [ContextCommandProgressItem] {
        state.visibleItems.filter {
            !dismissedRequestIDs.contains($0.requestID)
        }
    }

    /// 只在可见快照变化时进入测试或 AppKit 渲染边界。
    private func renderIfNeeded() {
        let visibleItems = currentlyPresentedItems
        guard visibleItems != lastRenderedItems else {
            return
        }
        lastRenderedItems = visibleItems

        render(visibleItems, ContextCommandProgressActions(
            cancel: { [weak self] requestID in self?.requestCancellation(requestID: requestID) },
            dismiss: { [weak self] in self?.dismissVisibleItems() }
        ))
    }
}

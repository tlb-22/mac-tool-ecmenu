import Foundation

// MARK: - ==================== 进度状态 ====================

/// 长时间右键命令在共享任务窗口中的不可变显示事实。
nonisolated struct ContextCommandProgressItem: Equatable, Sendable {
    /// 主应用本地任务标识，也是任务行的稳定身份。
    let requestID: UUID

    /// 名称、图标和外部应用依赖的唯一声明。
    let descriptor: ContextCommandDescriptor

    /// 命令开始时已经确定的总项目数。
    let totalUnitCount: Int

    /// 已经到达成功或失败终态的项目数。
    fileprivate(set) var completedUnitCount: Int

    /// 用户已经请求取消，Feature 尚未结束当前安全边界。
    fileprivate(set) var isCancellationRequested: Bool

    /// 任务经过显示延迟后才进入窗口，快速任务不会闪现。
    fileprivate(set) var isVisible: Bool

    /// 只允许进度状态所有者创建已经通过开始条件检查的任务。
    fileprivate init(
        requestID: UUID,
        descriptor: ContextCommandDescriptor,
        totalUnitCount: Int
    ) {
        self.requestID = requestID
        self.descriptor = descriptor
        self.totalUnitCount = totalUnitCount
        completedUnitCount = 0
        isCancellationRequested = false
        isVisible = false
    }
}

/// 集中维护多个右键命令的进度状态，不包含 AppKit 副作用。
nonisolated struct ContextCommandProgressState: Equatable, Sendable {
    /// 按命令开始顺序保存全部仍在运行的进度任务。
    private(set) var items: [ContextCommandProgressItem] = []

    /// 当前需要呈现在共享窗口中的任务。
    var visibleItems: [ContextCommandProgressItem] {
        items.filter(\.isVisible)
    }

    /// 登记一个刚刚开始实际执行、支持协作取消的进度任务。
    /// - Parameters:
    ///   - requestID: Router 为本次右键请求分配的稳定身份。
    ///   - descriptor: 对应命令的完整产品描述。
    ///   - totalUnitCount: 已知且大于零的总项目数。
    mutating func begin(
        requestID: UUID,
        descriptor: ContextCommandDescriptor,
        totalUnitCount: Int
    ) {
        precondition(
            totalUnitCount > 0,
            "A progress task must contain at least one unit"
        )
        precondition(
            index(of: requestID) == nil,
            "A progress task was started more than once"
        )

        items.append(
            ContextCommandProgressItem(
                requestID: requestID,
                descriptor: descriptor,
                totalUnitCount: totalUnitCount
            )
        )
    }

    /// 让仍在运行的任务经过延迟后出现在窗口中。
    mutating func reveal(requestID: UUID) {
        guard let index = index(of: requestID) else {
            return
        }
        items[index].isVisible = true
    }

    /// 把一个到达终态的项目记入已完成数。
    mutating func advance(requestID: UUID) {
        guard let index = index(of: requestID) else {
            preconditionFailure("Cannot advance an unknown progress task")
        }
        precondition(
            items[index].completedUnitCount < items[index].totalUnitCount,
            "A progress task advanced beyond its declared total"
        )
        items[index].completedUnitCount += 1
    }

    /// 记录用户取消意图，Feature 会在下一个安全边界读取它。
    mutating func requestCancellation(requestID: UUID) {
        guard let index = index(of: requestID) else {
            return
        }
        items[index].isCancellationRequested = true
    }

    /// 查询 Feature 是否应在下一个安全边界停止。
    func isCancellationRequested(for requestID: UUID) -> Bool {
        guard let index = index(of: requestID) else {
            preconditionFailure(
                "Cannot query cancellation for an unknown progress task"
            )
        }
        return items[index].isCancellationRequested
    }

    /// 命令结束后移除对应任务行。
    mutating func finish(requestID: UUID) {
        items.removeAll { $0.requestID == requestID }
    }

    /// 查找稳定请求身份在有序任务列表中的位置。
    private func index(of requestID: UUID) -> Int? {
        items.firstIndex { $0.requestID == requestID }
    }
}

// MARK: - ==================== Feature 进度能力 ====================

/// 一次命令执行可以选择使用的进度与协作取消入口。
@MainActor
final class ContextCommandProgressReporter {
    /// 本次命令对应的共享任务中心。
    private let center: ContextCommandProgressCenter

    /// Router 分配的稳定请求身份。
    private let requestID: UUID

    /// Command 提供的名称、图标和应用依赖。
    private let descriptor: ContextCommandDescriptor

    /// 绑定请求身份、命令描述和共享任务中心。
    init(
        center: ContextCommandProgressCenter,
        requestID: UUID,
        descriptor: ContextCommandDescriptor
    ) {
        self.center = center
        self.requestID = requestID
        self.descriptor = descriptor
    }

    /// 用户确认参数并即将产生真实工作时开始可取消进度。
    /// - Parameter totalUnitCount: 批次中需要到达终态的项目数。
    func begin(totalUnitCount: Int) {
        center.begin(
            requestID: requestID,
            descriptor: descriptor,
            totalUnitCount: totalUnitCount
        )
    }

    /// 一个项目成功或失败后推进一次进度。
    func advance() {
        center.advance(requestID: requestID)
    }

    /// 查询用户是否已经请求在下一个安全边界取消。
    var isCancellationRequested: Bool {
        center.isCancellationRequested(for: requestID)
    }

    /// Invocation 结束时统一清理可能已经登记的进度任务。
    func finish() {
        center.finish(requestID: requestID)
    }
}

/// Handler 执行期间由稳定框架提供的可选能力集合。
nonisolated struct ContextCommandExecutionContext: Sendable {
    /// 只有主动调用 `begin` 的 Feature 才会产生进度界面。
    let progress: ContextCommandProgressReporter
}

// MARK: - ==================== 生命周期与显示延迟 ====================

/// 拥有全部右键命令进度状态、显示延迟和共享任务窗口。
@MainActor
final class ContextCommandProgressCenter {
    /// 主应用全部 Router 共享的唯一任务中心。
    static let shared = ContextCommandProgressCenter()

    /// 快速任务不显示窗口的统一延迟。
    nonisolated static let standardDisplayDelay: Duration = .seconds(1)

    /// 测试可以替换的显示延迟；生产环境使用统一的一秒阈值。
    private let displayDelay: Duration

    /// 测试可以替换的 AppKit 渲染边界；生产环境由窗口控制器呈现。
    private let renderOverride: (([ContextCommandProgressItem]) -> Void)?

    /// 当前仍在运行的纯进度状态。
    private var state = ContextCommandProgressState()

    /// 每个尚未显示任务对应的独立延迟任务。
    private var revealTasks: [UUID: Task<Void, Never>] = [:]

    /// 用户关闭窗口时已经可见的任务；后续新任务不继承隐藏状态。
    private var dismissedRequestIDs: Set<UUID> = []

    /// 最近一次交给渲染边界的快照，避免无可见变化时触碰 AppKit。
    private var lastRenderedItems: [ContextCommandProgressItem] = []

    /// 至少一个任务可见时才创建并保留窗口控制器。
    private var windowController: ContextCommandProgressWindowController?

    /// 创建进度中心，并允许测试替换延迟和渲染副作用。
    /// - Parameters:
    ///   - displayDelay: 任务从开始到可见之间的统一阈值。
    ///   - render: 接收可见快照的测试边界；省略时使用 AppKit 面板。
    init(
        displayDelay: Duration = standardDisplayDelay,
        render: (([ContextCommandProgressItem]) -> Void)? = nil
    ) {
        self.displayDelay = displayDelay
        renderOverride = render
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

        // 窗口正在响应自己的关闭动作，不从回调内再次调用 close()。
        windowController = nil
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

        if let renderOverride {
            renderOverride(visibleItems)
            return
        }

        guard !visibleItems.isEmpty else {
            windowController?.closeWhenEmpty()
            windowController = nil
            return
        }

        if windowController == nil {
            windowController = ContextCommandProgressWindowController(
                cancelAction: { [weak self] requestID in
                    self?.requestCancellation(requestID: requestID)
                },
                dismissAction: { [weak self] in
                    self?.dismissVisibleItems()
                }
            )
        }
        windowController?.update(with: visibleItems)
    }
}

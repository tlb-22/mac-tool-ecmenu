/**
 定义任务进度的纯状态模型，以及开始、显示、推进、取消和结束的状态转换。
 以请求身份维护有序任务，向展示层提供当前可见项目的值快照。
 */

import Foundation

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

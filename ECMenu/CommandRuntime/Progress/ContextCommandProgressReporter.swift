/**
 为一次命令执行绑定请求身份、命令描述与共享进度中心。
 向处理器提供开始、推进、协作取消查询和结束进度的受限入口。
 */

import Foundation

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

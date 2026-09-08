/**
 定义业务命令执行与结果呈现的通用处理器契约。
 将异步执行结果交给主执行器上的反馈阶段，并按需提供运行时能力。
 */

import Foundation

/// 一个能执行类型化命令并在主线程呈现结果的功能 Handler。
@MainActor
protocol ContextCommandHandling {
    /// Handler 接受的共享命令类型。
    associatedtype Command: ContextCommandPayload

    /// Handler 执行后产生的类型化结果。
    associatedtype Outcome: Sendable

    /// 离开调用方 Actor 执行命令，不直接呈现 UI。
    ///
    /// `@concurrent` 让命令在通用执行器上运行；Router 创建的原始 Task
    /// 贯穿整个 Handler，取消状态沿相同任务传播。
    @concurrent nonisolated func execute(_ command: Command) async -> Outcome

    /// 使用稳定执行框架提供的可选能力执行命令。
    ///
    /// 普通 Feature 继承默认实现即可；只有需要进度或协作取消的
    /// Feature 才覆盖此入口并主动开始进度。
    @concurrent nonisolated func execute(
        _ command: Command,
        context: ContextCommandExecutionContext
    ) async -> Outcome

    /// 在主线程唯一出口呈现命令结果。
    func present(_ outcome: Outcome, requestID: UUID)
}

extension ContextCommandHandling {
    /// 默认忽略可选执行能力，保持快速命令没有进度生命周期。
    @concurrent nonisolated func execute(
        _ command: Command,
        context: ContextCommandExecutionContext
    ) async -> Outcome {
        await execute(command)
    }
}

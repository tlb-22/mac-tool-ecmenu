/**
 从命令信封恢复类型化调用，并持有各次调用的异步执行任务。
 为每次执行分配本地身份以关联任务和进度，负责运行结束及销毁时的任务清理。
 */

import Foundation
import OSLog

/// 分开管理右键命令的类型恢复和异步任务生命周期。
@MainActor
final class ContextCommandRouter {
    /// 记录无法恢复为已注册类型化命令的请求。
    private let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "ContextCommandRouter"
    )

    /// 产品组合层提供的不可变 Handler 注册表。
    private let handlers: ContextCommandHandlers

    /// 主应用共享的可选命令进度中心。
    private let progressCenter: ContextCommandProgressCenter

    /// 已分派且仍在执行的右键命令任务；Feature 直接在这些任务中执行。
    private var inFlightTasks: [UUID: Task<Void, Never>] = [:]

    /// 注入独立进度中心，供隔离测试或其他明确生命周期使用。
    init(
        handlers: ContextCommandHandlers,
        progressCenter: ContextCommandProgressCenter
    ) {
        self.handlers = handlers
        self.progressCenter = progressCenter
    }

    /// 取消尚未完成的功能任务。
    deinit {
        inFlightTasks.values.forEach { $0.cancel() }
    }

    /// 在启动任务之前恢复类型化调用，不产生任何功能副作用。
    /// - Parameter command: 已通过连接身份验证的命令信封。
    /// - Returns: 已绑定具体命令和 Handler 的调用；无法恢复时为 `nil`。
    func prepare(
        _ command: ContextCommandEnvelope
    ) -> ContextCommandInvocation? {
        do {
            guard let invocation = try handlers.invocation(for: command) else {
                logger.error(
                    "No Handler registered for context command \(command.featureID.rawValue, privacy: .public)"
                )
                return nil
            }
            return invocation
        } catch {
            logger.error(
                "Could not decode context command \(command.featureID.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// 为已恢复的调用分配本地身份，并管理异步任务生命周期。
    /// - Parameter invocation: `prepare` 产生的类型化调用。
    func run(_ invocation: ContextCommandInvocation) {
        let requestID = UUID()

        let progress = ContextCommandProgressReporter(
            center: progressCenter,
            requestID: requestID,
            descriptor: invocation.descriptor
        )
        let context = ContextCommandExecutionContext(progress: progress)
        let task = Task { [weak self] in
            await invocation.run(requestID: requestID, context: context)
            self?.inFlightTasks[requestID] = nil
        }
        inFlightTasks[requestID] = task
    }
}

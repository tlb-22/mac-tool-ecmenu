import Foundation
import OSLog

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

/// 隐藏具体命令和结果类型，供通用 Router 统一执行。
@MainActor
struct ContextCommandInvocation {
    /// 共享任务窗口和其他产品界面共用的命令描述。
    let descriptor: ContextCommandDescriptor

    /// 已绑定命令、Handler 和呈现出口的完整调用。
    private let runClosure: @MainActor (
        UUID,
        ContextCommandExecutionContext
    ) async -> Void

    /// 把一个类型化命令和它的 Handler 组合为通用调用。
    /// - Parameters:
    ///   - command: 已经通过跨进程验证的功能命令。
    ///   - handler: 执行并呈现该命令的具体功能 Handler。
    init<Handler: ContextCommandHandling>(
        _ command: Handler.Command,
        handler: Handler
    ) {
        descriptor = Handler.Command.descriptor
        runClosure = { requestID, context in
            let outcome = await handler.execute(command, context: context)
            context.progress.finish()

            guard !Task.isCancelled else {
                return
            }
            handler.present(outcome, requestID: requestID)
        }
    }

    /// 执行已擦除类型的功能调用。
    /// - Parameter requestID: 用于反馈和诊断关联的主应用本地任务标识。
    func run(
        requestID: UUID,
        context: ContextCommandExecutionContext
    ) async {
        await runClosure(requestID, context)
    }
}

/// 隐藏具体命令和结果类型，并负责从通用信封恢复 Handler 输入。
@MainActor
struct AnyContextCommandHandler {
    /// Handler 接受的命令身份，也是运行时路由键。
    let descriptor: ContextCommandDescriptor

    /// 类型擦除后的命令解码与 Invocation 构造。
    private let invocationClosure: @MainActor (
        ContextCommandEnvelope
    ) throws -> ContextCommandInvocation

    /// 保留具体 Handler 的命令身份和类型化行为。
    /// - Parameter handler: 产品组合层注册的功能 Handler。
    init<Handler: ContextCommandHandling>(_ handler: Handler) {
        descriptor = Handler.Command.descriptor
        invocationClosure = { command in
            let decoded = try command.decode(as: Handler.Command.self)
            return ContextCommandInvocation(decoded, handler: handler)
        }
    }

    /// 为身份已经匹配的通用命令信封创建类型化调用。
    func invocation(
        for command: ContextCommandEnvelope
    ) throws -> ContextCommandInvocation {
        try invocationClosure(command)
    }
}

/// 把顺序书写的具体 Handler 收集为产品执行注册表。
@resultBuilder
@MainActor
enum ContextCommandHandlerBuilder {
    /// result builder 中间阶段使用的类型擦除 Handler 序列。
    typealias Component = [AnyContextCommandHandler]

    /// 将一个具体 Handler 转换为统一注册项。
    static func buildExpression<Handler: ContextCommandHandling>(
        _ expression: Handler
    ) -> Component {
        [AnyContextCommandHandler(expression)]
    }

    /// 按声明顺序拼接产品 Handler。
    static func buildBlock(_ components: Component...) -> Component {
        components.flatMap { $0 }
    }
}

/// 同时为命令执行和主应用状态页提供单一产品注册源。
@MainActor
struct ContextCommandHandlers {
    /// 状态页按注册顺序展示的完整命令目录。
    let descriptors: [ContextCommandDescriptor]

    /// 按稳定 ID 索引的类型擦除 Handler。
    private let handlers: [ContextCommandFeatureID: AnyContextCommandHandler]

    /// 使用声明式 Handler 列表创建不可变注册表。
    /// - Parameter content: 当前产品支持的全部主应用执行端。
    init(
        @ContextCommandHandlerBuilder content: () -> [AnyContextCommandHandler]
    ) {
        let registeredHandlers = content()
        let featureIDs = registeredHandlers.map(\.descriptor.id)
        precondition(
            Set(featureIDs).count == featureIDs.count,
            "A context-command Handler was registered more than once"
        )

        descriptors = registeredHandlers.map(\.descriptor)
        handlers = Dictionary(
            uniqueKeysWithValues: registeredHandlers.map {
                ($0.descriptor.id, $0)
            }
        )
    }

    /// 按稳定 ID 查找 Handler，并恢复类型化 Invocation。
    func invocation(
        for command: ContextCommandEnvelope
    ) throws -> ContextCommandInvocation? {
        try handlers[command.featureID]?.invocation(for: command)
    }
}

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

    /// 使用主应用共享进度中心装配产品 Router。
    /// - Parameter handlers: 同时提供类型化路由和界面目录的注册表。
    init(handlers: ContextCommandHandlers) {
        self.handlers = handlers
        progressCenter = .shared
    }

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

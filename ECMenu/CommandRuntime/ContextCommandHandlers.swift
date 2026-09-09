/**
 对具体命令处理器做类型擦除，并构建可按命令载荷分发的处理器集合。
 在保留载荷与结果类型配对的前提下，为路由器提供统一调用入口。
 */

import Foundation

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

/// 保存产品装配生成的运行时注册表，供命令路由和状态页读取。
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
        self.init(registeredHandlers: content())
    }

    init(registeredHandlers: [AnyContextCommandHandler]) {
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

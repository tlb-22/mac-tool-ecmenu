/**
 封装已经匹配的命令与处理器，隐藏具体载荷和结果类型。
 串联执行、进度收尾与反馈，并使用调用方提供的请求身份关联结果。
 */

import Foundation

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

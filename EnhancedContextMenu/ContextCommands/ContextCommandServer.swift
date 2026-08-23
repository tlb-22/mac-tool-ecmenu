import Foundation
import OSLog

/// 接收并执行经过身份验证的 Finder Extension 单次右键命令。
@MainActor
final class ContextCommandServer: NSObject {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EnhancedContextMenu",
        category: "ContextCommand"
    )

    /// 由产品组合层提供的类型化命令路由器。
    private let router: ContextCommandRouter

    /// 生产组合中唯一的定向、双向身份验证 socket Server。
    private var transportServer: AuthenticatedLocalSocketServer?

    // MARK: - ==================== 生命周期 ====================

    /// 创建不绑定生产 socket 的纯请求处理器，供单元测试使用。
    /// - Parameter router: 接收已验证命令的产品组合路由器。
    init(router: ContextCommandRouter) {
        self.router = router
        super.init()
    }

    /// 注入生产依赖并开始监听 App Group 中的定向 socket。
    /// - Parameters:
    ///   - router: 接收已验证命令的产品组合路由器。
    ///   - menuConfiguration: 主应用菜单配置的真相源。
    convenience init(
        router: ContextCommandRouter,
        menuConfiguration: MenuConfigurationController
    ) {
        self.init(router: router)

        let serverReference = WeakIPCReference(self)
        let configurationReference = WeakIPCReference(menuConfiguration)

        do {
            transportServer = try AuthenticatedLocalSocketServer(
                expectedClientSigningIdentifier:
                    ApplicationIPC.finderExtensionSigningIdentifier
            ) { request, reply in
                Task { @MainActor in
                    guard let server = serverReference.value else {
                        reply(nil)
                        return
                    }

                    switch request {
                    case let .contextCommand(commandRequest):
                        server.process(commandRequest)
                    case .menuConfiguration:
                        guard
                            let menuConfiguration =
                                configurationReference.value
                        else {
                            reply(nil)
                            return
                        }
                        reply(menuConfiguration.configuration)
                    }
                }
            }

            // Extension 可能在 Server 准备完成前尝试过初始拉取；准备完成后
            // 只广播一个无数据唤醒信号，让它重新走已验证的定向连接。
            MenuConfigurationChannel.signalConfigurationChange()
        } catch {
            logger.error(
                "Could not start authenticated local IPC: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    /// 关闭监听 socket；活跃进程退出时不留下过期端点。
    deinit {
        transportServer?.stop()
    }

    // MARK: - ==================== 请求处理管线 ====================

    /// 验证当前 schema、恢复类型化调用，并交给主应用本地任务系统。
    /// 该方法不向 Extension 返回接管状态或业务执行结果。
    /// - Parameter request: 已在 transport 层通过对端身份验证的请求。
    func process(_ request: ContextCommandRequest) {
        guard request.schemaVersion == ContextCommandRequest.currentSchemaVersion else {
            logger.error("Ignored an unsupported context command request")
            return
        }

        guard let invocation = router.prepare(request.command) else {
            logger.error(
                "Ignored a context command whose typed invocation could not be restored"
            )
            return
        }

        // 跨进程消息不携带可靠性交付身份；UUID 只属于主应用内部的
        // 任务、进度、取消和诊断生命周期。
        let requestID = UUID()
        guard router.run(invocation, requestID: requestID) else {
            logger.error(
                "Could not start context command request \(requestID.uuidString, privacy: .public)"
            )
            return
        }
    }
}

/// Sendable closure 中使用的弱引用盒，避免 Server 与 handler 形成所有权环。
nonisolated private final class WeakIPCReference<Value: AnyObject>:
    @unchecked Sendable
{
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

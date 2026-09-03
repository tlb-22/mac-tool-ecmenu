import Foundation
import OSLog

/// 接收经过身份验证的 Extension 请求，并分派命令或返回菜单配置。
@MainActor
final class ApplicationIPCServer {
    private let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "ApplicationIPC"
    )

    /// 生产组合中唯一的定向、双向身份验证 socket Server。
    private var transportServer: AuthenticatedLocalSocketServer?

    // MARK: - ==================== 生命周期 ====================

    /// 注入生产依赖并开始监听 App Group 中的定向 socket。
    /// - Parameters:
    ///   - router: 接收已验证命令的产品组合路由器。
    ///   - menuConfiguration: 主应用菜单配置的真相源。
    init(
        router: ContextCommandRouter,
        menuConfiguration: MenuConfigurationController
    ) {
        do {
            transportServer = try AuthenticatedLocalSocketServer(
                expectedClientSigningIdentifier:
                    ApplicationIPC.finderExtensionSigningIdentifier,
                contextCommandSink: { request in
                    Task { @MainActor in
                        guard
                            let invocation = router.prepare(request.command)
                        else {
                            return
                        }
                        router.run(invocation)
                    }
                },
                menuConfigurationProvider: { reply in
                    Task { @MainActor in
                        reply(menuConfiguration.configuration)
                    }
                }
            )

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
}

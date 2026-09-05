import Foundation
import OSLog

/// 应用生命周期持有的监听资源，测试可注入失败和恢复。
nonisolated protocol ApplicationIPCListening: AnyObject, Sendable {
    func stop()
}

extension AuthenticatedLocalSocketServer: ApplicationIPCListening {}

/// 接收经过身份验证的 Extension 请求，并分派命令或返回菜单配置。
@MainActor
final class ApplicationIPCServer {
    enum State {
        case stopped
        case listening(any ApplicationIPCListening)
        case failed(Error)
    }

    typealias MakeTransport = (
        @escaping @Sendable (ApplicationIPCError) -> Void
    ) throws -> any ApplicationIPCListening

    private let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "ApplicationIPC"
    )

    /// 运行和失败状态由应用侧唯一所有者管理；底层失败完成清理后才上报。
    private(set) var state = State.stopped
    private let makeTransport: MakeTransport
    private let didStart: () -> Void

    // MARK: - ==================== 生命周期 ====================

    /// 注入生产依赖；应用生命周期明确调用 startIfNeeded 开始监听。
    /// - Parameters:
    ///   - router: 接收已验证命令的产品组合路由器。
    ///   - menuConfiguration: 主应用菜单配置的真相源。
    convenience init(
        router: ContextCommandRouter,
        menuConfiguration: MenuConfigurationController
    ) {
        self.init(makeTransport: { didFail in
            try AuthenticatedLocalSocketServer(
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
                },
                didFail: didFail
            )
        }, didStart: MenuConfigurationChannel.signalConfigurationChange)
    }

    init(makeTransport: @escaping MakeTransport, didStart: @escaping () -> Void) {
        self.makeTransport = makeTransport
        self.didStart = didStart
    }

    /// 首次启动以及用户再次打开应用时恢复不可用的监听，不重放任何命令。
    func startIfNeeded() {
        if case .listening = state { return }
        do {
            let transport = try makeTransport { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleListenerFailure(error)
                }
            }
            state = .listening(transport)
            // 初次或恢复监听都唤醒配置副本，重新拉取权威快照。
            didStart()
        } catch {
            recordFailure(error)
        }
    }

    private func handleListenerFailure(_ error: ApplicationIPCError) {
        guard case .listening = state else { return }
        recordFailure(error)
    }

    private func recordFailure(_ error: Error) {
        state = .failed(error)
        logger.error(
            "Authenticated local IPC is unavailable: \(error.localizedDescription, privacy: .private)"
        )
    }

    /// 关闭监听 socket；活跃进程退出时不留下过期端点。
    deinit {
        if case let .listening(transport) = state { transport.stop() }
    }
}

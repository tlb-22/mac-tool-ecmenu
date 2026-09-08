/**
 接管一个已接受连接，完成对端认证与请求解码，并调用命令入口或等待菜单快照提供者。
 每条连接的响应等待与字节传输共用期限，处理结束统一关闭 descriptor；业务任务独立于连接存活。
 */

import Foundation
import OSLog

/// 接管单个已接受连接；认证、请求和响应共用同一期限，descriptor 只在此关闭。
nonisolated final class AuthenticatedLocalSocketConnectionHandler: Sendable {
    private let logger = Logger(
        subsystem: ApplicationIPC.applicationSigningIdentifier,
        category: "AuthenticatedLocalIPC"
    )
    private let peerValidator: LocalSocketPeerValidator
    private let contextCommandSink: AuthenticatedLocalSocketServer.ContextCommandSink
    private let commandMenuSettingsProvider: AuthenticatedLocalSocketServer.CommandMenuSettingsProvider
    private let connectionTimeout: TimeInterval

    init(
        expectedClientSigningIdentifier: String,
        contextCommandSink: @escaping AuthenticatedLocalSocketServer.ContextCommandSink,
        commandMenuSettingsProvider: @escaping AuthenticatedLocalSocketServer.CommandMenuSettingsProvider,
        connectionTimeout: TimeInterval
    ) throws {
        peerValidator = try LocalSocketPeerValidator(
            expectedSigningIdentifier: expectedClientSigningIdentifier
        )
        self.contextCommandSink = contextCommandSink
        self.commandMenuSettingsProvider = commandMenuSettingsProvider
        self.connectionTimeout = connectionTimeout
    }

    func handle(_ descriptor: Int32) {
        defer { LocalSocketIO.close(descriptor) }

        do {
            let deadline = LocalSocketDeadline(timeout: connectionTimeout)
            // Server 必须先验证身份，错误进程的字节不会进入 JSON 解码或路由。
            try peerValidator.validate(connectedSocket: descriptor)
            try LocalSocketIO.writeFrame(
                LocalSocketAuthenticationReadyAcknowledgment.acknowledgmentPayload,
                to: descriptor,
                deadline: deadline
            )
            let requestData = try LocalSocketIO.readFrame(from: descriptor, deadline: deadline)
            let request = try JSONDecoder().decode(
                ApplicationIPCRequest.self,
                from: requestData
            )

            switch request {
            case let .contextCommand(request):
                // 命令是单向消息：交给应用层后立即关闭连接，不等待接管
                // 回执或业务执行结果。
                contextCommandSink(request)
            case .commandMenuSettings:
                let waiter = CommandMenuSettingsResponseWaiter()
                commandMenuSettingsProvider { configuration in
                    waiter.fulfill(configuration)
                }
                let configuration = try waiter.wait(deadline: deadline)

                let responseData = try JSONEncoder().encode(configuration)
                try LocalSocketIO.writeFrame(responseData, to: descriptor, deadline: deadline)
            }
        } catch {
            logger.error(
                "Rejected local IPC connection: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// 把 MainActor 上取得的菜单配置交还给单个后台查询连接。
nonisolated private final class CommandMenuSettingsResponseWaiter:
    @unchecked Sendable
{
    private enum State {
        case waiting
        case fulfilled(Result<CommandMenuSettingsSnapshot, Error>)
    }

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var state = State.waiting

    func fulfill(_ response: Result<CommandMenuSettingsSnapshot, Error>) {
        lock.lock()
        guard case .waiting = state else {
            lock.unlock()
            preconditionFailure(
                "A menu-configuration request was fulfilled more than once"
            )
        }
        state = .fulfilled(response)
        lock.unlock()
        semaphore.signal()
    }

    func wait(deadline: LocalSocketDeadline) throws -> CommandMenuSettingsSnapshot {
        guard semaphore.wait(timeout: deadline.dispatchTime) == .success else {
            throw ApplicationIPCError.deadlineExceeded
        }
        lock.lock()
        defer { lock.unlock() }
        guard case let .fulfilled(response) = state else {
            preconditionFailure(
                "A menu-configuration wait resumed without a response"
            )
        }
        return try response.get()
    }
}

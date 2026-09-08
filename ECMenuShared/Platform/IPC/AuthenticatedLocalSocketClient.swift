/**
 为每次命令发送或快照查询建立独立认证连接，协调端点定位、对端验证、认证 ACK 和请求传输。
 连接由单次操作唯一关闭；命令写出即结束，查询继续在同一期限内取得完整响应。
 */

import Foundation

/// 每次操作建立一条定向连接，并在发送正文前验证主应用身份。
nonisolated final class AuthenticatedLocalSocketClient:
    ContextCommandSending,
    CommandMenuConfigRequesting,
    @unchecked Sendable
{
    private let socketURL: URL
    private let peerValidator: LocalSocketPeerValidator
    private let connectionTimeout: TimeInterval
    private let queue = DispatchQueue(
        label: "\(ApplicationIPC.applicationSigningIdentifier).ipc-client",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// 创建生产客户端；显式 URL 仅供隔离测试使用。
    init(
        expectedServerSigningIdentifier: String,
        socketURL: URL? = nil,
        connectionTimeout: TimeInterval = LocalSocketDeadline.defaultTimeout
    ) throws {
        self.socketURL = try socketURL ?? ApplicationIPC.socketURL()
        self.connectionTimeout = connectionTimeout
        peerValidator = try LocalSocketPeerValidator(
            expectedSigningIdentifier: expectedServerSigningIdentifier
        )
    }

    func send(
        _ request: ContextCommandRequest,
        completion: @escaping @Sendable (
            Result<Void, Error>
        ) -> Void
    ) {
        queue.async { [self] in
            completion(Result { try transmit(request) })
        }
    }

    func fetchCommandMenuConfig(
        completion: @escaping @Sendable (
            Result<CommandMenuConfigSnapshot, Error>
        ) -> Void
    ) {
        queue.async { [self] in
            completion(Result { try fetchCommandMenuConfig() })
        }
    }

    /// 同步写入一条命令，不读取回执或业务结果。
    func transmit(_ request: ContextCommandRequest) throws {
        try withVerifiedConnection { descriptor, deadline in
            try write(.contextCommand(request), to: descriptor, deadline: deadline)
        }
    }

    /// 集成测试和异步包装共享的同步菜单配置查询。
    func fetchCommandMenuConfig() throws -> CommandMenuConfigSnapshot {
        try withVerifiedConnection { descriptor, deadline in
            try write(.commandMenuConfig, to: descriptor, deadline: deadline)
            let responseData = try LocalSocketIO.readFrame(from: descriptor, deadline: deadline)
            return try JSONDecoder().decode(
                CommandMenuConfigSnapshot.self,
                from: responseData
            )
        }
    }

    /// 建立连接并等待双方都在任何业务正文发出前完成身份验证。
    private func withVerifiedConnection<Result>(
        _ operation: (Int32, LocalSocketDeadline) throws -> Result
    ) throws -> Result {
        let deadline = LocalSocketDeadline(timeout: connectionTimeout)
        let descriptor = try LocalSocketIO.connect(to: socketURL, deadline: deadline)
        defer { LocalSocketIO.close(descriptor) }

        // Client 先验证 Server；Server 验证 Client 后才发送认证就绪 ACK。
        // 等待该 ACK 会让 Client 保持连接，避免 Server 读取动态对端身份前
        // Client 已经写完并关闭连接。
        try peerValidator.validate(connectedSocket: descriptor)
        let acknowledgmentPayload = try LocalSocketIO.readFrame(
            from: descriptor,
            deadline: deadline
        )
        try LocalSocketAuthenticationReadyAcknowledgment
            .validateAcknowledgmentPayload(acknowledgmentPayload)
        return try operation(descriptor, deadline)
    }

    /// 编码并完整写入一条应用协议请求。
    private func write(
        _ request: ApplicationIPCRequest,
        to descriptor: Int32,
        deadline: LocalSocketDeadline
    ) throws {
        let requestData = try JSONEncoder().encode(request)
        try LocalSocketIO.writeFrame(requestData, to: descriptor, deadline: deadline)
    }
}

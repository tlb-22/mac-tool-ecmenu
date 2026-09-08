/**
 规定服务端完成客户端身份验证后发送的空认证就绪消息，并验证客户端收到的正文形状。
 该握手使客户端保持连接直到双方认证结束，业务接管与执行结果不由此消息确认。
 */

import Foundation

/// Server 在任何业务正文发送前返回的认证就绪 ACK。
nonisolated enum LocalSocketAuthenticationReadyAcknowledgment {
    /// 空 ACK 只确认 Server 已验证 Client，不携带接管或业务状态。
    static let acknowledgmentPayload = Data()

    static func validateAcknowledgmentPayload(_ payload: Data) throws {
        guard payload == acknowledgmentPayload else {
            throw ApplicationIPCError.invalidAuthenticationReadyAcknowledgment
        }
    }
}

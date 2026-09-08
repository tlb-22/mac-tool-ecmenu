/**
 集中表达本地通信在端点、认证、连接等待、framing 与系统调用边界的预期失败及诊断文本。
 错误值保留判断与记录所需的系统信息，业务操作结果由对应能力另行建模。
 */

import Foundation

/// IPC 建立、身份验证、framing 或编解码失败。
nonisolated enum ApplicationIPCError: Error, Equatable {
    case applicationGroupUnavailable
    case socketPathTooLong
    case socketPathOccupied
    case invalidSocketFile
    case peerAuditTokenLength(actual: Int, expected: Int)
    case peerTaskUnavailable
    case peerCodeRequirementMismatch
    case codeRequirement(operation: String, reason: String)
    case posix(operation: String, code: Int32)
    case connectionClosed
    case deadlineExceeded
    case frameLengthOverflow
    case invalidAuthenticationReadyAcknowledgment
}

nonisolated extension ApplicationIPCError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .applicationGroupUnavailable:
            "The IPC App Group container is unavailable"
        case .socketPathTooLong:
            "The IPC socket path exceeds the platform limit"
        case .socketPathOccupied:
            "Another process already owns the IPC socket"
        case .invalidSocketFile:
            "The IPC path is occupied by a non-socket file"
        case let .peerAuditTokenLength(actual, expected):
            "The peer audit token has length \(actual), expected \(expected)"
        case .peerTaskUnavailable:
            "The peer audit token no longer identifies a running task"
        case .peerCodeRequirementMismatch:
            "The peer does not satisfy the required code-signing identity"
        case let .codeRequirement(operation, reason):
            "\(operation) failed: \(reason)"
        case let .posix(operation, code):
            "\(operation) failed with errno \(code)"
        case .connectionClosed:
            "The IPC connection closed before a complete message"
        case .deadlineExceeded:
            "The IPC connection did not complete within its deadline"
        case .frameLengthOverflow:
            "The IPC frame length cannot be represented by this process"
        case .invalidAuthenticationReadyAcknowledgment:
            "The IPC authentication-ready acknowledgment is invalid"
        }
    }
}

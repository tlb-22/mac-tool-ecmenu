/**
 从已连接 socket 的内核审计身份验证对端运行代码，统一双方使用的精确签名要求。
 验证同时约束 signing identifier、当前 Team、开发签名类别和动态有效标志，失败在业务正文前终止连接。
 */

import Darwin
import Foundation
import LightweightCodeRequirements
import Security

/// 从内核连接身份建立并执行精确的运行态轻量代码要求。
nonisolated final class LocalSocketPeerValidator: @unchecked Sendable {
    /// 由系统在目标运行进程上直接求值的类型化代码要求。
    private let requirement: ProcessCodeRequirement

    init(expectedSigningIdentifier: String) throws {
        precondition(
            !expectedSigningIdentifier.isEmpty,
            "The expected code-signing identity must not be empty"
        )

        do {
            requirement = try ProcessCodeRequirement.allOf {
                SigningIdentifier(expectedSigningIdentifier)
                TeamIdentifierMatchesCurrentProcess()
                ValidationCategory(.development)
                ProcessCodeSigningFlags.isSuperset(
                    of: [.isDynamicallyValid, .isSigned]
                )
            }
        } catch {
            throw ApplicationIPCError.codeRequirement(
                operation: "ProcessCodeRequirement.allOf",
                reason: String(describing: error)
            )
        }
    }

    /// 在读取任何正文前验证 connected socket 的动态对端身份。
    func validate(connectedSocket: Int32) throws {
        var auditToken = audit_token_t()
        var tokenLength = socklen_t(MemoryLayout<audit_token_t>.size)
        let tokenResult = withUnsafeMutablePointer(to: &auditToken) {
            getsockopt(
                connectedSocket,
                SOL_LOCAL,
                LOCAL_PEERTOKEN,
                $0,
                &tokenLength
            )
        }
        guard tokenResult == 0 else {
            throw Self.posixError("getsockopt(LOCAL_PEERTOKEN)")
        }
        guard tokenLength == MemoryLayout<audit_token_t>.size else {
            throw ApplicationIPCError.peerAuditTokenLength(
                actual: Int(tokenLength),
                expected: MemoryLayout<audit_token_t>.size
            )
        }

        guard let peerTask = SecTaskCreateWithAuditToken(nil, auditToken) else {
            throw ApplicationIPCError.peerTaskUnavailable
        }

        let matches: Bool
        do {
            matches = try SecTaskValidateForRequirement(
                task: peerTask,
                requirement: requirement
            )
        } catch {
            throw ApplicationIPCError.codeRequirement(
                operation: "SecTaskValidateForRequirement",
                reason: String(describing: error)
            )
        }
        guard matches else {
            throw ApplicationIPCError.peerCodeRequirementMismatch
        }
    }

    private static func posixError(_ operation: String) -> ApplicationIPCError {
        ApplicationIPCError.posix(operation: operation, code: errno)
    }
}

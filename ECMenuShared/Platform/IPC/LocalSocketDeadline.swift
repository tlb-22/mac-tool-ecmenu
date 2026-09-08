/**
 为一条连接建立单调时钟截止时间，并为 readiness 等待提供向上取整的剩余毫秒。
 所有传输步骤共享原截止时间，零碎字节或系统调用重试不会延长该预算。
 */

import Foundation

/// 一条连接的传输预算；不包括命令接管后的业务执行。
nonisolated struct LocalSocketDeadline: Sendable {
    static let defaultTimeout: TimeInterval = 5
    let dispatchTime: DispatchTime

    init(timeout: TimeInterval) {
        precondition(timeout > 0 && timeout.isFinite)
        dispatchTime = .now() + timeout
    }

    func remainingMilliseconds() throws -> Int32 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard dispatchTime.uptimeNanoseconds > now else {
            throw ApplicationIPCError.deadlineExceeded
        }
        let remaining = dispatchTime.uptimeNanoseconds - now
        return Int32(min((remaining + 999_999) / 1_000_000, UInt64(Int32.max)))
    }
}

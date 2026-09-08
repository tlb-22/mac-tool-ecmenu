/**
 在精确字节 I/O 之上实现八字节大端长度前缀，将完整正文与 Unix stream 相互转换。
 读写复用调用者的同一连接期限，正文长度超出进程可表示范围时明确拒绝。
 */

import Foundation

/// Unix stream 上使用的固定八字节大端长度前缀。
nonisolated private enum ApplicationIPCFrame {
    static let headerByteCount = MemoryLayout<UInt64>.size

    /// 为一段 JSON 正文添加长度前缀。
    static func encode(payload: Data) -> Data {
        var encodedLength = UInt64(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &encodedLength) { Data($0) }
        frame.append(payload)
        return frame
    }
}

/// 精确字节读写之上的八字节长度 framing；复用连接期限。
nonisolated extension LocalSocketIO {
    static func writeFrame(
        _ payload: Data,
        to descriptor: Int32,
        deadline: LocalSocketDeadline
    ) throws {
        try write(ApplicationIPCFrame.encode(payload: payload), to: descriptor, deadline: deadline)
    }

    static func readFrame(from descriptor: Int32, deadline: LocalSocketDeadline) throws -> Data {
        let header = try read(
            count: ApplicationIPCFrame.headerByteCount,
            from: descriptor,
            deadline: deadline
        )
        var encodedLength: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &encodedLength) { destination in
            header.copyBytes(to: destination)
        }
        let payloadLength = UInt64(bigEndian: encodedLength)
        guard payloadLength <= UInt64(Int.max) else {
            throw ApplicationIPCError.frameLengthOverflow
        }
        return try read(count: Int(payloadLength), from: descriptor, deadline: deadline)
    }
}

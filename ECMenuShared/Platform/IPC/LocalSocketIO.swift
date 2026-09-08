/**
 封装 Unix socket 建连、地址构造和有期限的精确字节读写，统一处理短读短写与可重试系统中断。
 原语把成功创建的 descriptor 交给调用者唯一持有，连接建立失败则在当前边界释放。
 */

import Darwin
import Foundation

/// Unix socket 连接与精确字节 I/O；调用者唯一持有并关闭 descriptor。
nonisolated enum LocalSocketIO {
    static func connect(
        to socketURL: URL,
        deadline: LocalSocketDeadline = LocalSocketDeadline(timeout: LocalSocketDeadline.defaultTimeout)
    ) throws -> Int32 {
        let descriptor = try makeSocket()
        do {
            try setNonBlocking(descriptor)
            try withAddress(for: socketURL.path) { address, length in
                if Darwin.connect(descriptor, address, length) != 0 {
                    guard errno == EINPROGRESS else { throw posixError("connect") }
                    try waitUntilReady(descriptor, events: Int16(POLLOUT), deadline: deadline)
                    var error: Int32 = 0
                    var length = socklen_t(MemoryLayout<Int32>.size)
                    guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else {
                        throw posixError("getsockopt(SO_ERROR)")
                    }
                    guard error == 0 else {
                        throw ApplicationIPCError.posix(operation: "connect", code: error)
                    }
                }
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    static func close(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        _ = Darwin.close(descriptor)
    }

    static func makeSocket() throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw posixError("socket")
        }

        var enabled: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            let error = posixError("setsockopt(SO_NOSIGPIPE)")
            close(descriptor)
            throw error
        }
        return descriptor
    }

    static func setNonBlocking(_ descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw posixError("fcntl(O_NONBLOCK)")
        }
    }

    static func withAddress<Result>(
        for path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
    ) throws -> Result {
        let pathBytes = path.utf8CString
        var address = sockaddr_un()
        let maximumPathBytes = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= maximumPathBytes else {
            throw ApplicationIPCError.socketPathTooLong
        }

        address.sun_family = sa_family_t(AF_UNIX)
        let addressLength = MemoryLayout<sockaddr_un>.offset(
            of: \.sun_path
        )! + pathBytes.count
        guard addressLength <= Int(UInt8.max) else {
            throw ApplicationIPCError.socketPathTooLong
        }
        address.sun_len = UInt8(addressLength)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }

        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) {
                try body($0, socklen_t(addressLength))
            }
        }
    }

    static func write(
        _ data: Data,
        to descriptor: Int32,
        deadline: LocalSocketDeadline
    ) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try waitUntilReady(descriptor, events: Int16(POLLOUT), deadline: deadline)
                let written = Darwin.send(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset,
                    MSG_DONTWAIT
                )
                if written < 0, errno == EINTR || errno == EAGAIN {
                    continue
                }
                guard written > 0 else {
                    throw written == 0
                        ? ApplicationIPCError.connectionClosed
                        : posixError("write")
                }
                offset += written
            }
        }
    }

    static func read(
        count: Int,
        from descriptor: Int32,
        deadline: LocalSocketDeadline
    ) throws -> Data {
        guard count > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            try waitUntilReady(descriptor, events: Int16(POLLIN), deadline: deadline)
            let received = bytes.withUnsafeMutableBytes { buffer in
                Darwin.recv(
                    descriptor,
                    buffer.baseAddress!.advanced(by: offset),
                    count - offset,
                    MSG_DONTWAIT
                )
            }
            if received < 0, errno == EINTR || errno == EAGAIN {
                continue
            }
            guard received > 0 else {
                throw received == 0
                    ? ApplicationIPCError.connectionClosed
                    : posixError("read")
            }
            offset += received
        }
        return Data(bytes)
    }

    /// 所有短读、短写共享同一个单调时钟期限，零碎字节不会不断延长等待。
    private static func waitUntilReady(
        _ descriptor: Int32,
        events: Int16,
        deadline: LocalSocketDeadline
    ) throws {
        while true {
            var descriptorState = pollfd(fd: descriptor, events: events, revents: 0)
            let result = Darwin.poll(&descriptorState, 1, try deadline.remainingMilliseconds())
            if result < 0, errno == EINTR { continue }
            guard result >= 0 else { throw posixError("poll") }
            guard result > 0 else { throw ApplicationIPCError.deadlineExceeded }
            guard descriptorState.revents & Int16(POLLNVAL) == 0 else {
                throw ApplicationIPCError.posix(operation: "poll", code: EBADF)
            }
            return
        }
    }

    static func posixError(_ operation: String) -> ApplicationIPCError {
        ApplicationIPCError.posix(operation: operation, code: errno)
    }
}

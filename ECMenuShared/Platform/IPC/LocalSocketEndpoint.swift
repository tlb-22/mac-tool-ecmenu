/**
 负责 Unix socket 的绑定、监听、接收与路径回收，使用跨进程锁序列化端点操作。
 绑定结果携带 device/inode 身份，停止时只删除自身端点；陈旧判断保留权限和资源失败的区别。
 */

import Darwin
import Foundation

/// 端点绑定、跨进程路径锁与 inode 所有权清理；不持有第二份 descriptor 状态。
nonisolated extension LocalSocketIO {
    /// `bind` 发现同名路径后，对现有 Unix socket 的精确探测结果。
    private enum OccupiedEndpointProbe {
        /// 路径仍由能够接受连接的 Server 使用。
        case active(descriptor: Int32)

        /// socket inode 仍在，但已经没有 Server 监听。
        case stale

        /// 路径在 `bind` 与探测之间消失，可以直接重试绑定。
        case disappeared
    }

    /// 绑定结果携带路径身份，防止旧 Server 删除新 Server 的同名端点。
    struct BoundSocket {
        let descriptor: Int32
        let fileIdentity: SocketFileIdentity
    }

    /// socket 文件的稳定文件系统身份。
    struct SocketFileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    static func listen(at socketURL: URL) throws -> BoundSocket {
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = try makeSocket()
        do {
            return try withEndpointLock(at: socketURL) {
                do {
                    try bind(descriptor, to: socketURL)
                } catch let error as ApplicationIPCError {
                    guard
                        case let .posix(_, code) = error,
                        code == EADDRINUSE
                    else {
                        throw error
                    }

                    switch try probeOccupiedEndpoint(at: socketURL) {
                    case .active(let activeDescriptor):
                        close(activeDescriptor)
                        throw ApplicationIPCError.socketPathOccupied
                    case .stale:
                        try removeStaleSocket(at: socketURL)
                    case .disappeared:
                        break
                    }
                    try bind(descriptor, to: socketURL)
                }

                guard Darwin.chmod(
                    socketURL.path,
                    S_IRUSR | S_IWUSR
                ) == 0 else {
                    throw posixError("chmod")
                }
                guard Darwin.listen(descriptor, SOMAXCONN) == 0 else {
                    throw posixError("listen")
                }
                try setNonBlocking(descriptor)
                return BoundSocket(
                    descriptor: descriptor,
                    fileIdentity: try socketFileIdentity(at: socketURL)
                )
            }
        } catch {
            close(descriptor)
            throw error
        }
    }

    /// 在与 bind/stale 清理相同的跨进程锁内关闭并删除自己的端点。
    static func stopListening(
        _ descriptor: Int32,
        at socketURL: URL,
        fileIdentity: SocketFileIdentity
    ) {
        do {
            try withEndpointLock(at: socketURL) {
                close(descriptor)
                removeSocketIfPresent(
                    at: socketURL,
                    matching: fileIdentity
                )
            }
        } catch {
            // 无法取得清理锁时仍必须释放内核 descriptor；下次启动会按
            // 文件类型验证并清理留下的 stale socket。
            close(descriptor)
        }
    }

    static func acceptConnection(_ descriptor: Int32) -> Result<Int32, ApplicationIPCError> {
        let connection = Darwin.accept(descriptor, nil, nil)
        return connection >= 0 ? .success(connection) : .failure(posixError("accept"))
    }

    private static func removeSocketIfPresent(
        at socketURL: URL,
        matching expectedIdentity: SocketFileIdentity
    ) {
        var information = stat()
        guard lstat(socketURL.path, &information) == 0 else {
            return
        }
        guard (information.st_mode & S_IFMT) == S_IFSOCK else {
            return
        }
        guard
            SocketFileIdentity(
                device: information.st_dev,
                inode: information.st_ino
            ) == expectedIdentity
        else {
            return
        }
        _ = Darwin.unlink(socketURL.path)
    }

    private static func bind(_ descriptor: Int32, to socketURL: URL) throws {
        try withAddress(for: socketURL.path) { address, length in
            guard Darwin.bind(descriptor, address, length) == 0 else {
                throw posixError("bind")
            }
        }
    }

    /// 只把内核明确报告为无监听者或路径消失的结果用于 stale 恢复。
    /// 其他连接错误可能来自权限或资源状态，必须原样交给调用方。
    private static func probeOccupiedEndpoint(
        at socketURL: URL
    ) throws -> OccupiedEndpointProbe {
        do {
            return .active(descriptor: try connect(to: socketURL))
        } catch let error as ApplicationIPCError {
            guard
                case let .posix(operation, code) = error,
                operation == "connect"
            else {
                throw error
            }

            switch code {
            case ECONNREFUSED:
                return .stale
            case ENOENT:
                return .disappeared
            default:
                throw error
            }
        }
    }

    private static func removeStaleSocket(at socketURL: URL) throws {
        var information = stat()
        guard lstat(socketURL.path, &information) == 0 else {
            if errno == ENOENT { return }
            throw posixError("lstat")
        }
        guard (information.st_mode & S_IFMT) == S_IFSOCK else {
            throw ApplicationIPCError.invalidSocketFile
        }
        guard Darwin.unlink(socketURL.path) == 0 else {
            throw posixError("unlink")
        }
    }

    /// 返回当前路径的 device/inode，供 Server 所有权检查。
    private static func socketFileIdentity(
        at socketURL: URL
    ) throws -> SocketFileIdentity {
        var information = stat()
        guard lstat(socketURL.path, &information) == 0 else {
            throw posixError("lstat")
        }
        guard (information.st_mode & S_IFMT) == S_IFSOCK else {
            throw ApplicationIPCError.invalidSocketFile
        }
        return SocketFileIdentity(
            device: information.st_dev,
            inode: information.st_ino
        )
    }

    /// 序列化同一路径的 stale 清理、bind 和 stop，关闭检查/删除竞态。
    private static func withEndpointLock<Result>(
        at socketURL: URL,
        _ body: () throws -> Result
    ) throws -> Result {
        let lockURL = socketURL.deletingLastPathComponent()
            .appendingPathComponent(".ipc.lock", isDirectory: false)
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw posixError("open(endpoint lock)")
        }
        defer { close(descriptor) }

        while Darwin.lockf(descriptor, F_LOCK, 0) != 0 {
            if errno == EINTR { continue }
            throw posixError("lockf(F_LOCK)")
        }
        defer { _ = Darwin.lockf(descriptor, F_ULOCK, 0) }
        return try body()
    }
}

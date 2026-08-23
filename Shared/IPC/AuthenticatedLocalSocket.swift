import Darwin
import Foundation
import LightweightCodeRequirements
import OSLog
import Security

/// 允许生产客户端和测试替身共享单向命令发送边界。
nonisolated protocol ContextCommandSending: AnyObject, Sendable {
    /// 单次发送命令；成功只表示请求已完整写入经过验证的连接。
    func send(
        _ request: ContextCommandRequest,
        completion: @escaping @Sendable (
            Result<Void, Error>
        ) -> Void
    )
}

/// 允许生产客户端和测试替身共享菜单配置查询边界。
nonisolated protocol MenuConfigurationRequesting: AnyObject, Sendable {
    /// 从经过双向身份验证的连接取得主应用当前配置。
    func fetchMenuConfiguration(
        completion: @escaping @Sendable (
            Result<MenuConfiguration, Error>
        ) -> Void
    )
}

/// Unix stream 上使用的固定八字节大端长度前缀。
nonisolated enum ApplicationIPCFrame {
    static let headerByteCount = MemoryLayout<UInt64>.size

    /// 为一段 JSON 正文添加长度前缀。
    static func encode(payload: Data) -> Data {
        var encodedLength = UInt64(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &encodedLength) { Data($0) }
        frame.append(payload)
        return frame
    }

    /// 从一帧完整数据中验证长度并恢复正文。
    static func decode(frame: Data) throws -> Data {
        guard frame.count >= headerByteCount else {
            throw ApplicationIPCError.invalidFrame
        }

        var encodedLength: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &encodedLength) { destination in
            frame.copyBytes(
                to: destination,
                from: 0..<headerByteCount
            )
        }
        let payloadLength = UInt64(bigEndian: encodedLength)
        guard
            payloadLength
                <= UInt64(Int.max - ApplicationIPCFrame.headerByteCount)
        else {
            throw ApplicationIPCError.frameLengthOverflow
        }

        let expectedCount = headerByteCount + Int(payloadLength)
        guard frame.count == expectedCount else {
            throw ApplicationIPCError.invalidFrame
        }
        return frame.subdata(in: headerByteCount..<expectedCount)
    }
}

/// Server 在任何业务正文发送前返回的认证就绪 ACK。
nonisolated private enum LocalSocketAuthenticationReadyAcknowledgment {
    /// 空 ACK 只确认 Server 已验证 Client，不携带接管或业务状态。
    static let acknowledgmentPayload = Data()

    static func validateAcknowledgmentPayload(_ payload: Data) throws {
        guard payload == acknowledgmentPayload else {
            throw ApplicationIPCError.invalidAuthenticationReadyAcknowledgment
        }
    }
}

/// 从内核连接身份建立并执行精确的运行态轻量代码要求。
nonisolated final class LocalSocketPeerValidator: @unchecked Sendable {
    /// 对端必须同时满足当前 Team 和这一精确 signing identifier。
    let expectedSigningIdentifier: String

    /// 由系统在目标运行进程上直接求值的类型化代码要求。
    private let requirement: ProcessCodeRequirement

    init(expectedSigningIdentifier: String) throws {
        guard !expectedSigningIdentifier.isEmpty else {
            throw ApplicationIPCError.invalidSigningIdentity
        }

        self.expectedSigningIdentifier = expectedSigningIdentifier
        do {
            requirement = try ProcessCodeRequirement.allOf {
                SigningIdentifier(expectedSigningIdentifier)
                TeamIdentifierMatchesCurrentProcess()
                ValidationCategory.in(.development, .developerID)
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

/// 每次操作建立一条定向连接，并在发送正文前验证主应用身份。
nonisolated final class AuthenticatedLocalSocketClient:
    ContextCommandSending,
    MenuConfigurationRequesting,
    @unchecked Sendable
{
    private let socketURL: URL
    private let peerValidator: LocalSocketPeerValidator
    private let queue = DispatchQueue(
        label: "\(ApplicationIPC.applicationSigningIdentifier).ipc-client",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// 创建生产客户端；显式 URL 仅供隔离测试使用。
    init(
        expectedServerSigningIdentifier: String,
        socketURL: URL? = nil
    ) throws {
        self.socketURL = try socketURL ?? ApplicationIPC.socketURL()
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

    func fetchMenuConfiguration(
        completion: @escaping @Sendable (
            Result<MenuConfiguration, Error>
        ) -> Void
    ) {
        queue.async { [self] in
            completion(Result { try fetchMenuConfiguration() })
        }
    }

    /// 同步写入一条命令，不读取回执或业务结果。
    func transmit(_ request: ContextCommandRequest) throws {
        try withVerifiedConnection { descriptor in
            try write(.contextCommand(request), to: descriptor)
        }
    }

    /// 集成测试和异步包装共享的同步菜单配置查询。
    func fetchMenuConfiguration() throws -> MenuConfiguration {
        try withVerifiedConnection { descriptor in
            try write(.menuConfiguration, to: descriptor)
            let responseData = try LocalSocketIO.readFrame(from: descriptor)
            return try JSONDecoder().decode(
                MenuConfiguration.self,
                from: responseData
            )
        }
    }

    /// 建立连接并等待双方都在任何业务正文发出前完成身份验证。
    private func withVerifiedConnection<Result>(
        _ operation: (Int32) throws -> Result
    ) throws -> Result {
        let descriptor = try LocalSocketIO.connect(to: socketURL)
        defer { LocalSocketIO.close(descriptor) }

        // Client 先验证 Server；Server 验证 Client 后才发送认证就绪 ACK。
        // 等待该 ACK 会让 Client 保持连接，避免 Server 读取动态对端身份前
        // Client 已经写完并关闭连接。
        try peerValidator.validate(connectedSocket: descriptor)
        let acknowledgmentPayload = try LocalSocketIO.readFrame(
            from: descriptor
        )
        try LocalSocketAuthenticationReadyAcknowledgment
            .validateAcknowledgmentPayload(acknowledgmentPayload)
        return try operation(descriptor)
    }

    /// 编码并完整写入一条应用协议请求。
    private func write(
        _ request: ApplicationIPCRequest,
        to descriptor: Int32
    ) throws {
        let requestData = try JSONEncoder().encode(request)
        try LocalSocketIO.writeFrame(requestData, to: descriptor)
    }
}

/// 在 App Group socket 上接收连接，并在解码前验证 Finder Extension 身份。
nonisolated final class AuthenticatedLocalSocketServer: @unchecked Sendable {
    typealias Handler = @Sendable (
        ApplicationIPCRequest,
        @escaping @Sendable (MenuConfiguration?) -> Void
    ) -> Void

    private let logger = Logger(
        subsystem: ApplicationIPC.applicationSigningIdentifier,
        category: "AuthenticatedLocalIPC"
    )
    private let socketURL: URL
    private let peerValidator: LocalSocketPeerValidator
    private let handler: Handler
    private let acceptQueue = DispatchQueue(
        label: "\(ApplicationIPC.applicationSigningIdentifier).ipc-server.accept",
        qos: .userInitiated
    )
    private let connectionQueue = DispatchQueue(
        label: "\(ApplicationIPC.applicationSigningIdentifier).ipc-server.connection",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let stateLock = NSLock()
    private var listenerDescriptor: Int32
    private let socketFileIdentity: LocalSocketIO.SocketFileIdentity
    private var stopped = false

    init(
        expectedClientSigningIdentifier: String,
        socketURL: URL? = nil,
        handler: @escaping Handler
    ) throws {
        self.socketURL = try socketURL ?? ApplicationIPC.socketURL()
        peerValidator = try LocalSocketPeerValidator(
            expectedSigningIdentifier: expectedClientSigningIdentifier
        )
        self.handler = handler
        let boundSocket = try LocalSocketIO.listen(at: self.socketURL)
        listenerDescriptor = boundSocket.descriptor
        socketFileIdentity = boundSocket.fileIdentity

        acceptQueue.async { [weak self] in
            self?.acceptConnections()
        }
    }

    deinit {
        stop()
    }

    /// 关闭监听端并删除自己创建的 socket 文件。
    func stop() {
        stateLock.lock()
        guard !stopped else {
            stateLock.unlock()
            return
        }
        stopped = true
        let descriptor = listenerDescriptor
        listenerDescriptor = -1
        stateLock.unlock()

        LocalSocketIO.stopListening(
            descriptor,
            at: socketURL,
            fileIdentity: socketFileIdentity
        )
    }

    private func acceptConnections() {
        while true {
            stateLock.lock()
            let descriptor = listenerDescriptor
            let shouldStop = stopped
            stateLock.unlock()
            guard !shouldStop, descriptor >= 0 else {
                return
            }

            let connection = Darwin.accept(descriptor, nil, nil)
            guard connection >= 0 else {
                if errno == EINTR {
                    continue
                }
                stateLock.lock()
                let stopped = self.stopped
                stateLock.unlock()
                if !stopped {
                    logger.error(
                        "accept failed with errno \(errno, privacy: .public)"
                    )
                }
                return
            }

            connectionQueue.async { [weak self] in
                self?.handleConnection(connection)
                    ?? LocalSocketIO.close(connection)
            }
        }
    }

    private func handleConnection(_ descriptor: Int32) {
        defer { LocalSocketIO.close(descriptor) }

        do {
            // Server 必须先验证身份，错误进程的字节不会进入 JSON 解码或路由。
            try peerValidator.validate(connectedSocket: descriptor)
            try LocalSocketIO.writeFrame(
                LocalSocketAuthenticationReadyAcknowledgment.acknowledgmentPayload,
                to: descriptor
            )
            let requestData = try LocalSocketIO.readFrame(from: descriptor)
            let request = try JSONDecoder().decode(
                ApplicationIPCRequest.self,
                from: requestData
            )

            switch request {
            case .contextCommand:
                // 命令是单向消息：交给应用层后立即关闭连接，不等待接管
                // 回执或业务执行结果。
                handler(request) { _ in }
            case .menuConfiguration:
                let waiter = MenuConfigurationResponseWaiter()
                handler(request) { configuration in
                    waiter.fulfill(configuration)
                }
                guard let configuration = waiter.wait() else {
                    return
                }

                let responseData = try JSONEncoder().encode(configuration)
                try LocalSocketIO.writeFrame(responseData, to: descriptor)
            }
        } catch {
            logger.error(
                "Rejected local IPC connection: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// 把 MainActor 上取得的菜单配置交还给单个后台查询连接。
nonisolated private final class MenuConfigurationResponseWaiter:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var response: MenuConfiguration?
    private var fulfilled = false

    func fulfill(_ response: MenuConfiguration?) {
        lock.lock()
        guard !fulfilled else {
            lock.unlock()
            return
        }
        fulfilled = true
        self.response = response
        lock.unlock()
        semaphore.signal()
    }

    func wait() -> MenuConfiguration? {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return response
    }
}

/// Unix socket 的路径、连接和精确读写原语。
nonisolated private enum LocalSocketIO {
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

    static func connect(to socketURL: URL) throws -> Int32 {
        let descriptor = try makeSocket()
        do {
            try withAddress(for: socketURL.path) { address, length in
                guard Darwin.connect(descriptor, address, length) == 0 else {
                    throw posixError("connect")
                }
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
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

                    if let activeDescriptor = try? connect(to: socketURL) {
                        close(activeDescriptor)
                        throw ApplicationIPCError.socketPathOccupied
                    }
                    try removeStaleSocket(at: socketURL)
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

    static func writeFrame(_ payload: Data, to descriptor: Int32) throws {
        try write(ApplicationIPCFrame.encode(payload: payload), to: descriptor)
    }

    static func readFrame(from descriptor: Int32) throws -> Data {
        let header = try read(
            count: ApplicationIPCFrame.headerByteCount,
            from: descriptor
        )
        var encodedLength: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &encodedLength) { destination in
            header.copyBytes(to: destination)
        }
        let payloadLength = UInt64(bigEndian: encodedLength)
        guard payloadLength <= UInt64(Int.max) else {
            throw ApplicationIPCError.frameLengthOverflow
        }
        return try read(count: Int(payloadLength), from: descriptor)
    }

    static func close(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        _ = Darwin.close(descriptor)
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

    private static func makeSocket() throws -> Int32 {
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

    private static func bind(_ descriptor: Int32, to socketURL: URL) throws {
        try withAddress(for: socketURL.path) { address, length in
            guard Darwin.bind(descriptor, address, length) == 0 else {
                throw posixError("bind")
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

    private static func withAddress<Result>(
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

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0, errno == EINTR {
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

    private static func read(
        count: Int,
        from descriptor: Int32
    ) throws -> Data {
        guard count > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let received = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(
                    descriptor,
                    buffer.baseAddress!.advanced(by: offset),
                    count - offset
                )
            }
            if received < 0, errno == EINTR {
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

    private static func posixError(_ operation: String) -> ApplicationIPCError {
        ApplicationIPCError.posix(operation: operation, code: errno)
    }
}

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

/// 每次操作建立一条定向连接，并在发送正文前验证主应用身份。
nonisolated final class AuthenticatedLocalSocketClient:
    ContextCommandSending,
    MenuConfigurationRequesting,
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
        try withVerifiedConnection { descriptor, deadline in
            try write(.contextCommand(request), to: descriptor, deadline: deadline)
        }
    }

    /// 集成测试和异步包装共享的同步菜单配置查询。
    func fetchMenuConfiguration() throws -> MenuConfiguration {
        try withVerifiedConnection { descriptor, deadline in
            try write(.menuConfiguration, to: descriptor, deadline: deadline)
            let responseData = try LocalSocketIO.readFrame(from: descriptor, deadline: deadline)
            return try JSONDecoder().decode(
                MenuConfiguration.self,
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

/// 在 App Group socket 上接收连接，并在解码前验证 Finder Extension 身份。
nonisolated final class AuthenticatedLocalSocketServer: @unchecked Sendable {
    typealias ContextCommandSink = @Sendable (ContextCommandRequest) -> Void
    typealias MenuConfigurationProvider = @Sendable (
        @escaping @Sendable (MenuConfiguration) -> Void
    ) -> Void
    typealias AcceptConnection = @Sendable (Int32) -> Result<Int32, ApplicationIPCError>

    private enum ListenerState {
        case listening
        case retryScheduled(DispatchWorkItem)
        case stopped(ApplicationIPCError?)
    }

    private let logger = Logger(
        subsystem: ApplicationIPC.applicationSigningIdentifier,
        category: "AuthenticatedLocalIPC"
    )
    private let socketURL: URL
    private let peerValidator: LocalSocketPeerValidator
    private let contextCommandSink: ContextCommandSink
    private let menuConfigurationProvider: MenuConfigurationProvider
    private let connectionTimeout: TimeInterval
    private let acceptConnection: AcceptConnection
    private let didFail: @Sendable (ApplicationIPCError) -> Void
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
    private let listenerDescriptor: Int32
    private let listenerSource: any DispatchSourceRead
    private var state = ListenerState.listening

    init(
        expectedClientSigningIdentifier: String,
        socketURL: URL? = nil,
        contextCommandSink: @escaping ContextCommandSink,
        menuConfigurationProvider: @escaping MenuConfigurationProvider,
        connectionTimeout: TimeInterval = LocalSocketDeadline.defaultTimeout,
        acceptConnection: @escaping AcceptConnection = { LocalSocketIO.acceptConnection($0) },
        didFail: @escaping @Sendable (ApplicationIPCError) -> Void = { _ in }
    ) throws {
        self.socketURL = try socketURL ?? ApplicationIPC.socketURL()
        peerValidator = try LocalSocketPeerValidator(
            expectedSigningIdentifier: expectedClientSigningIdentifier
        )
        self.contextCommandSink = contextCommandSink
        self.menuConfigurationProvider = menuConfigurationProvider
        self.connectionTimeout = connectionTimeout
        self.acceptConnection = acceptConnection
        self.didFail = didFail
        let boundSocket = try LocalSocketIO.listen(at: self.socketURL)
        listenerDescriptor = boundSocket.descriptor
        listenerSource = DispatchSource.makeReadSource(
            fileDescriptor: boundSocket.descriptor,
            queue: acceptQueue
        )
        listenerSource.setEventHandler { [weak self] in
            self?.acceptConnections()
        }
        let endpointURL = self.socketURL
        listenerSource.setCancelHandler { [weak self] in
            // Dispatch source 的取消回调晚于所有 accept 回调，descriptor
            // 只在这里关闭，避免 stop 与 accept 之间的 FD 重用竞态。
            LocalSocketIO.stopListening(
                boundSocket.descriptor,
                at: endpointURL,
                fileIdentity: boundSocket.fileIdentity
            )
            self?.reportListenerFailure()
        }
        listenerSource.activate()
    }

    deinit {
        stop()
    }

    /// 关闭监听端并删除自己创建的 socket 文件。
    func stop() {
        stopListening(failure: nil)
    }

    private func acceptConnections() {
        while true {
            stateLock.lock()
            let isListening: Bool
            if case .listening = state { isListening = true } else { isListening = false }
            stateLock.unlock()
            guard isListening else { return }

            switch acceptConnection(listenerDescriptor) {
            case let .success(connection):
                connectionQueue.async { [weak self] in
                    self?.handleConnection(connection)
                        ?? LocalSocketIO.close(connection)
                }
            case let .failure(error):
                guard case let .posix(_, code) = error else {
                    stopListening(failure: error)
                    return
                }
                switch code {
                case EINTR, ECONNABORTED:
                    continue
                case EAGAIN:
                    return
                case EMFILE, ENFILE, ENOBUFS, ENOMEM:
                    scheduleAcceptRetry()
                    return
                default:
                    stopListening(failure: error)
                    return
                }
            }
        }
    }

    /// 资源短缺时暂停 ready source，避免内核持续报告可读导致忙循环。
    private func scheduleAcceptRetry() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard case .listening = state else { return }
        let retry = DispatchWorkItem { [weak self] in
            guard let self else { return }
            stateLock.lock()
            defer { stateLock.unlock() }
            guard case .retryScheduled = state else { return }
            state = .listening
            listenerSource.resume()
        }
        state = .retryScheduled(retry)
        listenerSource.suspend()
        acceptQueue.asyncAfter(deadline: .now() + 0.1, execute: retry)
    }

    private func stopListening(failure: ApplicationIPCError?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if case .stopped = state { return }
        let retry: DispatchWorkItem?
        if case let .retryScheduled(work) = state { retry = work } else { retry = nil }
        state = .stopped(failure)
        retry?.cancel()
        listenerSource.cancel()
        if retry != nil { listenerSource.resume() }
    }

    private func reportListenerFailure() {
        stateLock.lock()
        let failure: ApplicationIPCError?
        if case let .stopped(error) = state { failure = error } else { failure = nil }
        stateLock.unlock()
        if let failure { didFail(failure) }
    }

    private func handleConnection(_ descriptor: Int32) {
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
            case .menuConfiguration:
                let waiter = MenuConfigurationResponseWaiter()
                menuConfigurationProvider { configuration in
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
nonisolated private final class MenuConfigurationResponseWaiter:
    @unchecked Sendable
{
    private enum State {
        case waiting
        case fulfilled(MenuConfiguration)
    }

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var state = State.waiting

    func fulfill(_ response: MenuConfiguration) {
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

    func wait(deadline: LocalSocketDeadline) throws -> MenuConfiguration {
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
        return response
    }
}

/// Unix socket 的路径、连接和精确读写原语。
nonisolated enum LocalSocketIO {
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

    private static func setNonBlocking(_ descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw posixError("fcntl(O_NONBLOCK)")
        }
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

    private static func write(
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

    private static func read(
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

    private static func posixError(_ operation: String) -> ApplicationIPCError {
        ApplicationIPCError.posix(operation: operation, code: errno)
    }
}

/**
 拥有本地监听端点、Dispatch source 与接收状态，将连接交给独立处理器并协调资源短缺后的恢复。
 监听 descriptor 只在 source 取消完成后关闭，端点清理结束才报告致命失败。
 */

import Darwin
import Foundation

/// 在 App Group socket 上接收连接，并在解码前验证 Finder Extension 身份。
nonisolated final class AuthenticatedLocalSocketServer: @unchecked Sendable {
    typealias ContextCommandSink = @Sendable (ContextCommandRequest) -> Void
    typealias CommandMenuConfigProvider = @Sendable (
        @escaping @Sendable (Result<CommandMenuConfigSnapshot, Error>) -> Void
    ) -> Void
    typealias AcceptConnection = @Sendable (Int32) -> Result<Int32, ApplicationIPCError>

    private enum ListenerState {
        case listening
        case retryScheduled(DispatchWorkItem)
        case stopped(ApplicationIPCError?)
    }

    private let socketURL: URL
    private let connectionHandler: AuthenticatedLocalSocketConnectionHandler
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
        commandMenuConfigProvider: @escaping CommandMenuConfigProvider,
        connectionTimeout: TimeInterval = LocalSocketDeadline.defaultTimeout,
        acceptConnection: @escaping AcceptConnection = { LocalSocketIO.acceptConnection($0) },
        didFail: @escaping @Sendable (ApplicationIPCError) -> Void = { _ in }
    ) throws {
        self.socketURL = try socketURL ?? ApplicationIPC.socketURL()
        connectionHandler = try AuthenticatedLocalSocketConnectionHandler(
            expectedClientSigningIdentifier: expectedClientSigningIdentifier,
            contextCommandSink: contextCommandSink,
            commandMenuConfigProvider: commandMenuConfigProvider,
            connectionTimeout: connectionTimeout
        )
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
        connectionHandler.handle(descriptor)
    }
}

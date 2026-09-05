import Darwin
import Foundation
import XCTest
@testable import ECMenu

/// 验证右键命令 wire、定向 IPC framing 与双向身份要求。
final class ContextCommandTransportTests: XCTestCase {
    func testEveryConcreteCommandEnvelopeWireRoundTrips() throws {
        let firstPath = try XCTUnwrap(
            AbsoluteFilePath(path: "/test/first")
        )
        let secondPath = try XCTUnwrap(
            AbsoluteFilePath(path: "/test/second")
        )
        let selection = try XCTUnwrap(
            FinderItemSelection(paths: [firstPath.path, secondPath.path])
        )

        try assertEnvelopeWireRoundTrip(
            CreateNewTextFileCommand(directoryPath: firstPath)
        )
        try assertEnvelopeWireRoundTrip(
            try XCTUnwrap(CopyPathCommand(paths: [firstPath, secondPath]))
        )
        try assertEnvelopeWireRoundTrip(
            HideItemsCommand(selection: selection)
        )
        try assertEnvelopeWireRoundTrip(
            ShowItemsCommand(selection: selection)
        )
        try assertEnvelopeWireRoundTrip(
            CompressImagesCommand(selection: selection)
        )
        try assertEnvelopeWireRoundTrip(
            OpenInVSCodeCommand(targetPath: firstPath)
        )
        try assertEnvelopeWireRoundTrip(
            OpenInITerm2Command(targetPath: secondPath)
        )
    }

    func testInvalidCommandIdentityAndEmptyCopyPathWireAreRejected() throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CopyPathCommand.self,
                from: Data("[]".utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ContextCommandFeatureID.self,
                from: Data(#"{"rawValue":""}"#.utf8)
            )
        )
    }

    func testAbsolutePathAndNonEmptySelectionValidationAndRoundTrip() throws {
        XCTAssertNil(AbsoluteFilePath(path: "relative/path"))
        XCTAssertNil(FinderItemSelection(paths: []))
        XCTAssertNil(FinderItemSelection(paths: ["relative/path"]))

        let expected = try XCTUnwrap(
            FinderItemSelection(paths: ["/test/first", "/test/second"])
        )
        let encoded = try JSONEncoder().encode(expected)
        XCTAssertEqual(
            try JSONDecoder().decode(FinderItemSelection.self, from: encoded),
            expected
        )

        let emptyItems = try JSONEncoder().encode([String]())
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                FinderItemSelection.self,
                from: emptyItems
            )
        )
    }

    func testCommandRequestWireRoundTrip() throws {
        let request = try makeRequest()
        let wireRequest = ApplicationIPCRequest.contextCommand(request)

        XCTAssertEqual(
            try JSONDecoder().decode(
                ApplicationIPCRequest.self,
                from: JSONEncoder().encode(wireRequest)
            ),
            wireRequest
        )
    }

    func testMenuConfigurationWireRoundTrip() throws {
        let request = ApplicationIPCRequest.menuConfiguration
        XCTAssertEqual(
            try JSONDecoder().decode(
                ApplicationIPCRequest.self,
                from: JSONEncoder().encode(request)
            ),
            request
        )

        let configuration = MenuConfiguration(
            isEnabled: false,
            hiddenFeatureIDs: ["new-text-file"]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                MenuConfiguration.self,
                from: JSONEncoder().encode(configuration)
            ),
            configuration
        )
    }

    func testMatchingRuntimeIdentityAllowsMenuConfigurationQuery() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { _ in
                XCTFail("A configuration query reached the command sink")
            },
            menuConfigurationProvider: { reply in reply(.standard) }
        )
        defer { server.stop() }

        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        )
        let configuration = try await Task.detached {
            try client.fetchMenuConfiguration()
        }.value

        XCTAssertEqual(configuration, .standard)
    }

    func testPermissionFailureDoesNotRemoveAnActiveSocketAsStale() throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { _ in },
            menuConfigurationProvider: { _ in }
        )
        defer {
            _ = Darwin.chmod(socketURL.path, S_IRUSR | S_IWUSR)
            server.stop()
        }

        XCTAssertEqual(Darwin.chmod(socketURL.path, 0), 0)

        XCTAssertThrowsError(
            try AuthenticatedLocalSocketServer(
                expectedClientSigningIdentifier:
                    ApplicationIPC.applicationSigningIdentifier,
                socketURL: socketURL,
                contextCommandSink: { _ in },
                menuConfigurationProvider: { _ in }
            )
        ) { error in
            guard
                case let ApplicationIPCError.posix(operation, code) = error
            else {
                return XCTFail(
                    "Expected the connect permission error, got \(error)"
                )
            }
            XCTAssertEqual(operation, "connect")
            XCTAssertEqual(code, EACCES)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: socketURL.path))
    }

    func testMatchingRuntimeIdentityAllowsOneWayCommand() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let routed = expectation(description: "Command reached the handler")
        let expected = try makeRequest()
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { request in
                XCTAssertEqual(request, expected)
                routed.fulfill()
            },
            menuConfigurationProvider: { _ in
                XCTFail("A command reached the configuration provider")
            }
        )
        defer { server.stop() }

        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        )
        try await Task.detached {
            try client.transmit(expected)
        }.value

        // 完整测试会并行启动多个 macOS test host；为后台 accept queue
        // 留出调度余量。该等待只属于测试，不是产品投递超时。
        await fulfillment(of: [routed], timeout: 3)
    }

    func testConcurrentOneWayCommandsAllReachHandlerExactlyOnce() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let requestCount = 8
        let expectedRequests = try (0..<requestCount).map { index in
            try makeRequest(path: "/test/concurrent-\(index)")
        }
        let routed = expectation(
            description: "Every concurrent command reached the handler"
        )
        routed.expectedFulfillmentCount = requestCount
        routed.assertForOverFulfill = true
        let transmissionsCompleted = expectation(
            description: "Every concurrent command finished sending"
        )
        transmissionsCompleted.expectedFulfillmentCount = requestCount
        transmissionsCompleted.assertForOverFulfill = true
        let requestRecorder = LockedIPCRequestRecorder()
        let failureRecorder = LockedIPCTransmissionFailureRecorder()
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { request in
                requestRecorder.append(request)
                routed.fulfill()
            },
            menuConfigurationProvider: { _ in
                XCTFail("A command reached the configuration provider")
            }
        )
        defer { server.stop() }

        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        )
        for request in expectedRequests {
            client.send(request) { result in
                if case let .failure(error) = result {
                    failureRecorder.append(error)
                }
                transmissionsCompleted.fulfill()
            }
        }

        // 并发发送和后台路由都属于测试等待；有界等待避免单个
        // 阻塞连接使整个测试宿主永久停留。
        await fulfillment(
            of: [transmissionsCompleted, routed],
            timeout: 5
        )

        let transmissionFailures = failureRecorder.snapshot
        XCTAssertTrue(
            transmissionFailures.isEmpty,
            "Every concurrent send must succeed: "
                + transmissionFailures.joined(separator: "; ")
        )

        let receivedRequests = requestRecorder.snapshot
        XCTAssertEqual(receivedRequests.count, expectedRequests.count)
        for expected in expectedRequests {
            XCTAssertEqual(
                receivedRequests.filter { $0 == expected }.count,
                1,
                "Each unique command must be routed exactly once"
            )
        }
    }

    func testServerRejectsWrongOneWayPeerBeforeRouting() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let routed = expectation(description: "Request reached the handler")
        routed.isInverted = true
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.finderExtensionSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { _ in routed.fulfill() },
            menuConfigurationProvider: { _ in routed.fulfill() }
        )
        defer { server.stop() }

        // Server 不会向错误身份发送认证就绪 ACK，因此 Client 必须在
        // 写入业务正文前观察到失败，Finder 层才能播放提示音。
        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        )
        let request = try makeRequest()
        let result = await Task.detached {
            Result { try client.transmit(request) }
        }.value

        if case .success = result {
            XCTFail("The rejected Client reported a successful send")
        }
        await fulfillment(of: [routed], timeout: 0.1)
    }

    func testClientRejectsWrongServerIdentityBeforeSending() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let routed = expectation(description: "Request reached the handler")
        routed.isInverted = true
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { _ in routed.fulfill() },
            menuConfigurationProvider: { _ in routed.fulfill() }
        )
        defer { server.stop() }

        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier:
                ApplicationIPC.finderExtensionSigningIdentifier,
            socketURL: socketURL
        )
        let request = try makeRequest()
        let result = await Task.detached {
            Result { try client.transmit(request) }
        }.value

        if case .success = result {
            XCTFail("The client trusted a Server with the wrong identifier")
        }
        await fulfillment(of: [routed], timeout: 0.1)
    }

    func testAcceptRecoversAfterResourceFailure() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let acceptor = FailingOnceIPCAcceptor(code: EMFILE)
        let routed = expectation(description: "Command after recovered accept")
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { _ in routed.fulfill() },
            menuConfigurationProvider: { $0(.standard) },
            acceptConnection: { acceptor.accept($0) },
            didFail: { error in XCTFail("Resource failure stopped the listener: \(error)") }
        )
        defer { server.stop() }
        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        )
        let request = try makeRequest()
        try await Task.detached { try client.transmit(request) }.value
        await fulfillment(of: [routed], timeout: 1)
    }

    func testStoppingOrReleasingListenerAfterResourceFailureCleansEndpoint() async throws {
        for termination in [ListenerTermination.stop, .release] {
            let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
            let exhausted = expectation(description: "Listener encountered resource exhaustion")
            let acceptor = ResourceExhaustedIPCAcceptor(firstFailure: exhausted)
            var server: AuthenticatedLocalSocketServer? = try AuthenticatedLocalSocketServer(
                expectedClientSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
                socketURL: socketURL,
                contextCommandSink: { _ in XCTFail("Resource-exhausted listener routed a command") },
                menuConfigurationProvider: { $0(.standard) },
                acceptConnection: { acceptor.accept($0) },
                didFail: { error in XCTFail("Stopping reported a fatal failure: \(error)") }
            )
            defer { server?.stop() }
            let releasedServer = WeakIPCListenerReference(server)
            let connection = try LocalSocketIO.connect(to: socketURL)
            defer { LocalSocketIO.close(connection) }
            await fulfillment(of: [exhausted], timeout: 1)

            // accept 替身返回后，让 source 进入 100 ms 的资源退避。
            // 替身始终返回 EMFILE，延迟调度也不会进入正常接收路径。
            try await Task.sleep(for: .milliseconds(20))
            switch termination {
            case .stop:
                server?.stop()
                server?.stop() // 停止必须幂等，不能对已取消 source 再次 resume。
            case .release:
                server = nil
            }

            let clock = ContinuousClock()
            let cleanupDeadline = clock.now.advanced(by: .seconds(1))
            while FileManager.default.fileExists(atPath: socketURL.path), clock.now < cleanupDeadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
            // 越过原重试时刻，确认取消的延迟任务不会重新打开或再次恢复 source。
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
            server = nil
            XCTAssertNil(releasedServer.value)
        }
    }

    func testFatalAcceptFailureReleasesEndpointBeforeReporting() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let failed = expectation(description: "Fatal listener failure reported after cleanup")
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { _ in XCTFail("Failed listener routed a command") },
            menuConfigurationProvider: { $0(.standard) },
            acceptConnection: { _ in .failure(.posix(operation: "accept", code: EBADF)) },
            didFail: { error in
                XCTAssertEqual(error, .posix(operation: "accept", code: EBADF))
                XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
                failed.fulfill()
            }
        )
        defer { server.stop() }
        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            connectionTimeout: 1
        )
        let result = await Task.detached { Result { try client.fetchMenuConfiguration() } }.value
        if case .success = result { XCTFail("A failed listener returned a configuration") }
        await fulfillment(of: [failed], timeout: 1)
    }

    func testTruncatedFramesAreRejected() throws {
        for bytes: [UInt8] in [[0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 5, 1, 2]] {
            var descriptors: [Int32] = [-1, -1]
            XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
            defer { descriptors.forEach { _ = Darwin.close($0) } }
            XCTAssertEqual(bytes.withUnsafeBytes {
                Darwin.write(descriptors[1], $0.baseAddress, $0.count)
            }, bytes.count)
            XCTAssertEqual(Darwin.shutdown(descriptors[1], SHUT_WR), 0)
            XCTAssertThrowsError(try LocalSocketIO.readFrame(
                from: descriptors[0], deadline: .init(timeout: 1)
            )) { error in
                XCTAssertEqual(error as? ApplicationIPCError, .connectionClosed)
            }
        }
    }

    func testInvalidAuthenticationAcknowledgmentPreventsCommandWrite() async throws {
        let server = try RawIPCServer { descriptor in
            try LocalSocketIO.writeFrame(Data([1]), to: descriptor, deadline: .init(timeout: 1))
            XCTAssertThrowsError(try LocalSocketIO.readFrame(from: descriptor, deadline: .init(timeout: 1))) {
                XCTAssertEqual($0 as? ApplicationIPCError, .connectionClosed)
            }
        }
        defer { server.stop() }
        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
            socketURL: server.socketURL
        )
        let request = try makeRequest()
        let result = await Task.detached { Result { try client.transmit(request) } }.value
        guard case let .failure(error) = result else { return XCTFail("Invalid ACK was accepted") }
        XCTAssertEqual(error as? ApplicationIPCError, .invalidAuthenticationReadyAcknowledgment)
        await fulfillment(of: [server.finished], timeout: 1)
    }

    func testSilentAuthenticatedPeerHasBoundedWait() async throws {
        let server = try RawIPCServer { descriptor in
            // 进程身份正确，但不发认证就绪 ACK；Client 应自行结束等待并关闭。
            XCTAssertThrowsError(try LocalSocketIO.readFrame(from: descriptor, deadline: .init(timeout: 1))) {
                XCTAssertEqual($0 as? ApplicationIPCError, .connectionClosed)
            }
        }
        defer { server.stop() }
        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
            socketURL: server.socketURL,
            connectionTimeout: 0.1
        )
        let result = await Task.detached { Result { try client.fetchMenuConfiguration() } }.value
        guard case let .failure(error) = result else { return XCTFail("Silent peer returned data") }
        XCTAssertEqual(error as? ApplicationIPCError, .deadlineExceeded)
        await fulfillment(of: [server.finished], timeout: 1)
    }

    func testConfigurationProviderWaitHasDeadline() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            contextCommandSink: { _ in XCTFail("Configuration became a command") },
            menuConfigurationProvider: { _ in },
            connectionTimeout: 0.1
        )
        defer { server.stop() }
        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier: ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL,
            connectionTimeout: 1
        )
        let result = await Task.detached { Result { try client.fetchMenuConfiguration() } }.value
        guard case let .failure(error) = result else { return XCTFail("Missing provider returned data") }
        XCTAssertEqual(error as? ApplicationIPCError, .connectionClosed)
    }

    @MainActor
    func testApplicationServerRecoversInitializationAndRuntimeFailure() async throws {
        var starts = 0
        var signals = 0
        var reportFailure: (@Sendable (ApplicationIPCError) -> Void)?
        let server = ApplicationIPCServer(makeTransport: { failure in
            starts += 1
            if starts == 1 { throw ApplicationIPCError.applicationGroupUnavailable }
            reportFailure = failure
            return TestIPCListener()
        }, didStart: { signals += 1 })
        XCTAssertEqual(starts, 0)
        server.startIfNeeded()
        guard case .failed = server.state else { return XCTFail("Startup failure was lost") }
        server.startIfNeeded()
        guard case .listening = server.state else { return XCTFail("Startup did not recover") }
        server.startIfNeeded()
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(signals, 1)
        reportFailure?(.posix(operation: "accept", code: EBADF))
        for _ in 0..<100 {
            if case .failed = server.state { break }
            await Task.yield()
        }
        guard case .failed = server.state else { return XCTFail("Runtime failure was lost") }
        server.startIfNeeded()
        guard case .listening = server.state else { return XCTFail("Runtime did not recover") }
        XCTAssertEqual(starts, 3)
        XCTAssertEqual(signals, 2)
    }

    private func makeRequest(
        path: String = "/test/parent"
    ) throws -> ContextCommandRequest {
        try ContextCommandRequest(
            command: CreateNewTextFileCommand(
                directoryPath: try XCTUnwrap(AbsoluteFilePath(path: path))
            )
        )
    }

    private func assertEnvelopeWireRoundTrip<Command>(
        _ expected: Command,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Command: ContextCommandPayload & Equatable {
        let envelope = try ContextCommandEnvelope(expected)
        let wireEnvelope = try JSONDecoder().decode(
            ContextCommandEnvelope.self,
            from: JSONEncoder().encode(envelope)
        )

        XCTAssertEqual(wireEnvelope, envelope, file: file, line: line)
        XCTAssertEqual(
            wireEnvelope.featureID,
            Command.descriptor.id,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try wireEnvelope.decode(as: Command.self),
            expected,
            file: file,
            line: line
        )
    }
}

nonisolated private enum ListenerTermination {
    case stop
    case release
}

nonisolated private final class WeakIPCListenerReference {
    weak var value: AuthenticatedLocalSocketServer?

    init(_ value: AuthenticatedLocalSocketServer?) { self.value = value }
}

nonisolated private final class ResourceExhaustedIPCAcceptor: @unchecked Sendable {
    private let lock = NSLock()
    private var firstFailure: XCTestExpectation?

    init(firstFailure: XCTestExpectation) { self.firstFailure = firstFailure }

    func accept(_ descriptor: Int32) -> Result<Int32, ApplicationIPCError> {
        lock.lock()
        let notification = firstFailure
        firstFailure = nil
        lock.unlock()
        notification?.fulfill()
        return .failure(.posix(operation: "accept", code: EMFILE))
    }
}

nonisolated private final class TestIPCListener: ApplicationIPCListening {
    func stop() {}
}

nonisolated private final class FailingOnceIPCAcceptor: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: Int32?

    init(code: Int32) { failure = code }

    func accept(_ descriptor: Int32) -> Result<Int32, ApplicationIPCError> {
        lock.lock()
        let code = failure
        failure = nil
        lock.unlock()
        if let code { return .failure(.posix(operation: "accept", code: code)) }
        return LocalSocketIO.acceptConnection(descriptor)
    }
}

/// 用当前测试宿主的真实签名身份验证 Client 的异常认证响应路径。
nonisolated private final class RawIPCServer: @unchecked Sendable {
    let socketURL: URL
    let finished = XCTestExpectation(description: "Raw IPC peer completed")
    private let source: any DispatchSourceRead

    init(handle: @escaping @Sendable (Int32) throws -> Void) throws {
        socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let endpoint = try LocalSocketIO.listen(at: socketURL)
        let endpointURL = socketURL
        let finished = self.finished
        source = DispatchSource.makeReadSource(fileDescriptor: endpoint.descriptor, queue: .global())
        source.setEventHandler { [source] in
            guard case let .success(connection) = LocalSocketIO.acceptConnection(endpoint.descriptor) else { return }
            source.cancel()
            defer { LocalSocketIO.close(connection); finished.fulfill() }
            do { try handle(connection) } catch { XCTFail("Raw IPC peer failed: \(error)") }
        }
        source.setCancelHandler {
            LocalSocketIO.stopListening(endpoint.descriptor, at: endpointURL, fileIdentity: endpoint.fileIdentity)
        }
        source.activate()
    }

    func stop() { source.cancel() }
    deinit { stop() }
}

/// 汇集并发 Client queues 返回的发送失败。
nonisolated private final class LockedIPCTransmissionFailureRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var failures: [String] = []

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }

    func append(_ error: Error) {
        lock.lock()
        failures.append(String(describing: error))
        lock.unlock()
    }
}

/// 汇集并发 Server connection queues 收到的类型化命令请求。
nonisolated private final class LockedIPCRequestRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var requests: [ContextCommandRequest] = []

    var snapshot: [ContextCommandRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func append(_ request: ContextCommandRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }
}

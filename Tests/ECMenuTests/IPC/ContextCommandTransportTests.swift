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

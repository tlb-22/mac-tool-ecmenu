import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证右键命令 wire、定向 IPC framing 与双向身份要求。
final class ContextCommandTransportTests: XCTestCase {
    func testTypedCommandEnvelopeRoundTrip() throws {
        let expected = CreateNewTextFileCommand(
            finderContext: .container(path: "/test/parent")
        )
        let envelope = try ContextCommandEnvelope(expected)

        XCTAssertEqual(envelope.featureID, CreateNewTextFileCommand.descriptor.id)
        XCTAssertEqual(
            envelope.decode(as: CreateNewTextFileCommand.self),
            expected
        )
    }

    func testSemanticFinderContextValidationAndRoundTrip() throws {
        XCTAssertNil(FinderItemSelection(paths: []))
        XCTAssertNil(FinderItemSelection(paths: ["relative/path"]))

        let expected = FinderContextSnapshot.items(
            selection: try XCTUnwrap(
                FinderItemSelection(paths: ["/test/first", "/test/second"])
            )
        )
        let encoded = try JSONEncoder().encode(expected)
        XCTAssertEqual(
            try JSONDecoder().decode(FinderContextSnapshot.self, from: encoded),
            expected
        )

        let emptyItems = try JSONSerialization.data(withJSONObject: [
            "kind": "items",
            "paths": [],
        ])
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                FinderContextSnapshot.self,
                from: emptyItems
            )
        )
    }

    func testCommandRequestWireRoundTrip() throws {
        let request = try makeRequest()
        XCTAssertEqual(request.schemaVersion, 5)
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

    func testStreamFrameRoundTripAndMalformedFrameRejection() throws {
        let payload = Data("context-command".utf8)
        let frame = ApplicationIPCFrame.encode(payload: payload)
        XCTAssertEqual(try ApplicationIPCFrame.decode(frame: frame), payload)

        XCTAssertThrowsError(
            try ApplicationIPCFrame.decode(frame: Data(frame.dropLast()))
        )

        var frameWithTrailingByte = frame
        frameWithTrailingByte.append(0)
        XCTAssertThrowsError(
            try ApplicationIPCFrame.decode(frame: frameWithTrailingByte)
        )
        XCTAssertThrowsError(
            try ApplicationIPCFrame.decode(frame: Data([0, 1, 2]))
        )
    }

    func testMatchingRuntimeIdentityAllowsMenuConfigurationQuery() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        ) { request, reply in
            XCTAssertEqual(request, .menuConfiguration)
            reply(.standard)
        }
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
        XCTAssertThrowsError(
            try LocalSocketPeerValidator(expectedSigningIdentifier: "")
        )
    }

    func testMatchingRuntimeIdentityAllowsOneWayCommand() async throws {
        let socketURL = try ProjectTestDirectory.makeUniqueSocketURL()
        let routed = expectation(description: "Command reached the handler")
        let expected = try makeRequest()
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        ) { request, _ in
            XCTAssertEqual(request, .contextCommand(expected))
            routed.fulfill()
        }
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
        let requestCount = 32
        let expectedRequests = try (0..<requestCount).map { index in
            try makeRequest(path: "/test/concurrent-\(index)")
        }
        let routed = expectation(
            description: "Every concurrent command reached the handler"
        )
        routed.expectedFulfillmentCount = requestCount
        routed.assertForOverFulfill = true
        let recorder = LockedIPCRequestRecorder()
        let server = try AuthenticatedLocalSocketServer(
            expectedClientSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        ) { request, _ in
            recorder.append(request)
            routed.fulfill()
        }
        defer { server.stop() }

        let client = try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            socketURL: socketURL
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            for request in expectedRequests {
                group.addTask {
                    try client.transmit(request)
                }
            }
            try await group.waitForAll()
        }

        // 测试等待只给后台 accept/connection queues 留出调度余量；产品
        // transport 仍不包含业务结果、重试或去重机制。
        await fulfillment(of: [routed], timeout: 5)

        let receivedRequests = recorder.snapshot
        XCTAssertEqual(receivedRequests.count, expectedRequests.count)
        for expected in expectedRequests {
            XCTAssertEqual(
                receivedRequests.filter {
                    $0 == .contextCommand(expected)
                }.count,
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
            socketURL: socketURL
        ) { _, _ in
            routed.fulfill()
        }
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
            socketURL: socketURL
        ) { _, _ in
            routed.fulfill()
        }
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
                finderContext: .container(path: path)
            )
        )
    }
}

/// 汇集并发 Server connection queues 收到的完整 IPC 请求。
nonisolated private final class LockedIPCRequestRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var requests: [ApplicationIPCRequest] = []

    var snapshot: [ApplicationIPCRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func append(_ request: ApplicationIPCRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }
}

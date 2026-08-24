import Foundation
import XCTest
@testable import EnhancedContextMenuFinderExtension

/// 验证一次 Finder 动作只产生一次单向命令发送。
final class ContextCommandClientTests: XCTestCase {
    @MainActor
    func testClientSendsCommandExactlyOnce() throws {
        let transport = RecordingContextCommandTransport()
        let client = ContextCommandClient(transport: transport)
        let expected = CreateNewTextFileCommand(
            directoryPath: try XCTUnwrap(
                AbsoluteFilePath(path: "/test/parent")
            )
        )

        client.send(expected)

        let requests = transport.recordedRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].command.decode(as: CreateNewTextFileCommand.self),
            expected
        )
    }
}

/// 记录单次命令写入，不提供回执、重试或业务结果。
nonisolated private final class RecordingContextCommandTransport:
    ContextCommandSending,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var requests: [ContextCommandRequest] = []

    var recordedRequests: [ContextCommandRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func send(
        _ request: ContextCommandRequest,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        lock.lock()
        requests.append(request)
        lock.unlock()
        completion(.success(()))
    }
}

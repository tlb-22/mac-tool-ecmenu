import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证 Server 只执行当前 schema 中能够恢复的单向命令。
@MainActor
final class ContextCommandServerTests: XCTestCase {
    func testValidRequestRunsOnce() async throws {
        let presented = expectation(description: "Presented command")
        let handler = ServerRecordingHandler(presented: presented)
        let server = makeServer(handler: handler)
        let request = try ContextCommandRequest(
            command: ServerRecordingCommand(value: "sent-once")
        )

        server.process(request)

        await fulfillment(of: [presented], timeout: 1)
        XCTAssertEqual(handler.presentedValues, ["sent-once"])
    }

    func testUndecodableCommandDoesNotRun() throws {
        let handler = ServerRecordingHandler()
        let server = makeServer(handler: handler)
        let request = ContextCommandRequest(
            command: try ContextCommandEnvelope(
                IncompatibleServerRecordingCommand(value: 42)
            )
        )

        server.process(request)

        XCTAssertTrue(handler.presentedValues.isEmpty)
    }

    func testOldSchemaDoesNotRun() throws {
        let handler = ServerRecordingHandler()
        let server = makeServer(handler: handler)
        let current = try ContextCommandRequest(
            command: ServerRecordingCommand(value: "old-schema")
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(current)
            ) as? [String: Any]
        )
        object["schemaVersion"] = ContextCommandRequest.currentSchemaVersion - 1
        let request = try JSONDecoder().decode(
            ContextCommandRequest.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        server.process(request)

        XCTAssertTrue(handler.presentedValues.isEmpty)
    }

    private func makeServer(
        handler: ServerRecordingHandler
    ) -> ContextCommandServer {
        ContextCommandServer(
            router: ContextCommandRouter(
                handlers: ContextCommandHandlers { handler }
            )
        )
    }
}

/// Server 测试使用的已注册命令。
private struct ServerRecordingCommand: ContextCommandPayload {
    static let descriptor = ContextCommandDescriptor(
        id: "server-recording-command",
        title: "Server Recording Command",
        icon: .systemSymbol(name: "record.circle")
    )

    let value: String
}

/// 故意复用已注册身份但使用不兼容负载结构的命令。
private struct IncompatibleServerRecordingCommand: ContextCommandPayload {
    static let descriptor = ServerRecordingCommand.descriptor
    let value: Int
}

/// 记录 Server 最终执行次数和内容的测试 Handler。
@MainActor
private final class ServerRecordingHandler: ContextCommandHandling {
    private let presented: XCTestExpectation?
    private(set) var presentedValues: [String] = []

    init(presented: XCTestExpectation? = nil) {
        self.presented = presented
    }

    @concurrent nonisolated func execute(
        _ command: ServerRecordingCommand
    ) async -> String {
        command.value
    }

    func present(_ outcome: String, requestID: UUID) {
        presentedValues.append(outcome)
        presented?.fulfill()
    }
}

import XCTest
@testable import EnhancedContextMenu

/// 验证声明式 Handler 注册、执行隔离和 Router 任务生命周期。
@MainActor
final class ContextCommandExecutionTests: XCTestCase {
    /// 进度任务应先保持隐藏，延迟显示后按总数封顶并正确移除。
    func testProgressStateLifecycle() {
        let requestID = UUID()
        let descriptor = progressDescriptor(
            id: "compress-images",
            title: "压缩图片",
            symbolName: "photo.badge.arrow.down"
        )
        var state = ContextCommandProgressState()

        XCTAssertTrue(
            state.begin(
                requestID: requestID,
                descriptor: descriptor,
                totalUnitCount: 3
            )
        )
        XCTAssertTrue(state.visibleItems.isEmpty)
        XCTAssertFalse(
            state.begin(
                requestID: requestID,
                descriptor: progressDescriptor(
                    id: "duplicate",
                    title: "重复任务"
                ),
                totalUnitCount: 3
            )
        )

        state.reveal(requestID: requestID)
        state.advance(requestID: requestID, by: 5)
        XCTAssertEqual(state.visibleItems.count, 1)
        XCTAssertEqual(state.visibleItems.first?.descriptor, descriptor)
        XCTAssertEqual(state.visibleItems.first?.completedUnitCount, 3)

        state.requestCancellation(requestID: requestID)
        XCTAssertTrue(state.isCancellationRequested(for: requestID))

        state.finish(requestID: requestID)
        XCTAssertTrue(state.items.isEmpty)
    }

    /// 空任务不进入进度状态，也不能产生取消状态。
    func testProgressStateRejectsEmptyTask() {
        let requestID = UUID()
        var state = ContextCommandProgressState()

        XCTAssertFalse(
            state.begin(
                requestID: requestID,
                descriptor: progressDescriptor(
                    id: "empty",
                    title: "空任务"
                ),
                totalUnitCount: 0
            )
        )
        state.requestCancellation(requestID: requestID)
        XCTAssertFalse(state.isCancellationRequested(for: requestID))
        XCTAssertTrue(state.items.isEmpty)
    }

    /// 延迟任务在获得执行机会前结束时，不应触发任何渲染副作用。
    func testProgressCenterDoesNotRenderFastCompletedTask() async {
        let requestID = UUID()
        var renderedSnapshots: [[ContextCommandProgressItem]] = []
        let center = ContextCommandProgressCenter(
            displayDelay: .zero,
            render: { renderedSnapshots.append($0) }
        )

        center.begin(
            requestID: requestID,
            descriptor: progressDescriptor(
                id: "fast",
                title: "快速任务"
            ),
            totalUnitCount: 1
        )
        center.advance(requestID: requestID)
        center.finish(requestID: requestID)
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(renderedSnapshots.isEmpty)
    }

    /// 多个任务应共享有序快照，并在各自推进和结束时独立更新。
    func testProgressCenterRendersMultipleTasksIndependently() async {
        let firstID = UUID()
        let secondID = UUID()
        var renderedSnapshots: [[ContextCommandProgressItem]] = []
        let center = ContextCommandProgressCenter(
            displayDelay: .zero,
            render: { renderedSnapshots.append($0) }
        )

        center.begin(
            requestID: firstID,
            descriptor: progressDescriptor(
                id: "first",
                title: "任务一"
            ),
            totalUnitCount: 2
        )
        center.begin(
            requestID: secondID,
            descriptor: progressDescriptor(
                id: "second",
                title: "任务二"
            ),
            totalUnitCount: 3
        )
        await waitUntil {
            renderedSnapshots.last?.map(\.requestID) == [firstID, secondID]
        }

        center.advance(requestID: secondID)
        XCTAssertEqual(
            renderedSnapshots.last?.last?.completedUnitCount,
            1
        )

        let renderCount = renderedSnapshots.count
        center.advance(requestID: UUID())
        center.finish(requestID: UUID())
        XCTAssertEqual(renderedSnapshots.count, renderCount)

        center.finish(requestID: firstID)
        XCTAssertEqual(renderedSnapshots.last?.map(\.requestID), [secondID])
        center.finish(requestID: secondID)
        XCTAssertEqual(renderedSnapshots.last, [])
    }

    /// 关闭窗口只隐藏当时任务，后来开始的任务仍应产生新的可见快照。
    func testProgressCenterDismissesOnlyCurrentlyVisibleRequestIDs() async {
        let dismissedID = UUID()
        let laterID = UUID()
        var renderedSnapshots: [[ContextCommandProgressItem]] = []
        let center = ContextCommandProgressCenter(
            displayDelay: .zero,
            render: { renderedSnapshots.append($0) }
        )

        center.begin(
            requestID: dismissedID,
            descriptor: progressDescriptor(
                id: "dismissed",
                title: "已隐藏任务"
            ),
            totalUnitCount: 2
        )
        await waitUntil {
            renderedSnapshots.last?.map(\.requestID) == [dismissedID]
        }
        center.dismissVisibleItems()
        XCTAssertEqual(renderedSnapshots.last, [])

        center.advance(requestID: dismissedID)
        XCTAssertEqual(renderedSnapshots.last, [])

        center.begin(
            requestID: laterID,
            descriptor: progressDescriptor(
                id: "later",
                title: "后来任务"
            ),
            totalUnitCount: 1
        )
        await waitUntil {
            renderedSnapshots.last?.map(\.requestID) == [laterID]
        }

        center.finish(requestID: dismissedID)
        center.finish(requestID: laterID)
        XCTAssertEqual(renderedSnapshots.last, [])
    }

    /// Router 应先纯恢复调用，直到显式 run 才开始功能副作用。
    func testRouterPreparesThenRunsRegisteredTypeErasedHandler() async throws {
        let presented = expectation(description: "Presented the command outcome")
        let handler = RecordingHandler(presented: presented)
        let handlers = ContextCommandHandlers {
            handler
        }
        let router = ContextCommandRouter(handlers: handlers)
        let requestID = UUID()

        let invocation = try XCTUnwrap(
            router.prepare(
                try ContextCommandEnvelope(
                    RecordingCommand(value: "result")
                )
            )
        )
        XCTAssertEqual(invocation.descriptor, RecordingCommand.descriptor)
        XCTAssertNil(handler.presentedOutcome)

        XCTAssertTrue(router.run(invocation, requestID: requestID))
        XCTAssertFalse(
            router.run(invocation, requestID: requestID),
            "run 必须在返回前登记 Task，且不能替换同一请求的在途任务"
        )

        await fulfillment(of: [presented], timeout: 1)
        XCTAssertEqual(handlers.descriptors, [RecordingCommand.descriptor])
        XCTAssertEqual(handler.presentedOutcome, "result")
        XCTAssertEqual(handler.presentedRequestID, requestID)
    }

    /// 未注册身份及同身份不兼容负载都不得产生可执行 Invocation。
    func testRouterRejectsUnknownAndUndecodableEnvelopes() throws {
        let handler = RecordingHandler()
        let router = ContextCommandRouter(
            handlers: ContextCommandHandlers { handler }
        )

        XCTAssertNil(
            router.prepare(
                try ContextCommandEnvelope(
                    UnknownRecordingCommand(value: "unknown")
                )
            )
        )
        XCTAssertNil(
            router.prepare(
                try ContextCommandEnvelope(
                    IncompatibleRecordingCommand(value: 42)
                )
            )
        )
        XCTAssertNil(handler.presentedOutcome)
    }

    /// Router 释放时应取消正在执行的同一个 Task，并跳过结果呈现。
    func testRouterCancellationReachesHandlerTask() async throws {
        let started = expectation(description: "Handler execution started")
        let cancelled = expectation(description: "Handler observed cancellation")
        let presented = expectation(description: "Cancelled result was presented")
        presented.isInverted = true

        let probe = CancellationProbe(
            started: started,
            cancelled: cancelled,
            presented: presented
        )
        let handlers = ContextCommandHandlers {
            CancellationHandler(probe: probe)
        }
        var router: ContextCommandRouter? = ContextCommandRouter(
            handlers: handlers
        )
        let invocation = try XCTUnwrap(
            router?.prepare(
                try ContextCommandEnvelope(
                    RecordingCommand(value: "cancel")
                )
            )
        )
        router?.run(invocation, requestID: UUID())

        await fulfillment(of: [started], timeout: 1)
        router = nil
        await fulfillment(of: [cancelled, presented], timeout: 1)
    }

    /// 等待零延迟进度任务让出 MainActor 并到达预期快照。
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("进度状态未在预期时间内到达", file: file, line: line)
    }
}

/// 为进度状态测试创建完整但互不冲突的命令描述。
private func progressDescriptor(
    id: String,
    title: String,
    symbolName: String = "gearshape"
) -> ContextCommandDescriptor {
    ContextCommandDescriptor(
        id: "progress-test-\(id)",
        title: title,
        icon: .systemSymbol(name: symbolName)
    )
}

/// 仅用于验证 Handler 注册表身份和信封解码的测试命令。
private struct RecordingCommand: ContextCommandPayload {
    /// 测试注册使用的稳定身份。
    static let descriptor = ContextCommandDescriptor(
        id: "recording-command",
        title: "Recording Command",
        icon: .systemSymbol(name: "record.circle")
    )

    /// Handler 原样返回的测试值。
    let value: String
}

/// 使用未注册身份验证 Router 不会产生 Invocation。
private struct UnknownRecordingCommand: ContextCommandPayload {
    /// 与产品注册表无关的稳定测试身份。
    static let descriptor = ContextCommandDescriptor(
        id: "unknown-recording-command",
        title: "Unknown Recording Command",
        icon: .systemSymbol(name: "questionmark.circle")
    )

    /// 测试负载。
    let value: String
}

/// 使用已注册身份但不同负载结构验证严格类型恢复。
private struct IncompatibleRecordingCommand: ContextCommandPayload {
    /// 故意复用 `RecordingCommand` 的身份。
    static let descriptor = RecordingCommand.descriptor

    /// 与 Handler 期待的 String 不兼容的测试负载。
    let value: Int
}

/// 仅用于验证 Router 和类型擦除 Invocation 的测试 Handler。
@MainActor
private final class RecordingHandler: ContextCommandHandling {
    /// 反馈出口执行时可选完成的测试期望。
    private let presented: XCTestExpectation?

    /// 反馈出口收到的类型化结果。
    private(set) var presentedOutcome: String?

    /// 反馈出口收到的主应用本地任务标识。
    private(set) var presentedRequestID: UUID?

    /// 注入用于观测反馈阶段的可选测试期望。
    init(presented: XCTestExpectation? = nil) {
        self.presented = presented
    }

    /// 返回测试命令中的值，模拟 Handler 的异步执行结果。
    @concurrent nonisolated func execute(
        _ command: RecordingCommand
    ) async -> String {
        command.value
    }

    /// 记录 Router 交付的结果和请求标识。
    func present(_ outcome: String, requestID: UUID) {
        presentedOutcome = outcome
        presentedRequestID = requestID
        presented?.fulfill()
    }
}

/// 允许并发执行阶段安全完成 XCTest 期望的测试探针。
nonisolated private final class CancellationProbe: @unchecked Sendable {
    /// Handler 进入执行阶段时完成。
    let started: XCTestExpectation

    /// Handler 在同一个 Task 中观察到取消时完成。
    let cancelled: XCTestExpectation

    /// 若 Router 错误呈现已取消结果则完成；测试中设置为反向期望。
    let presented: XCTestExpectation

    /// 注入完整生命周期的三个观测点。
    init(
        started: XCTestExpectation,
        cancelled: XCTestExpectation,
        presented: XCTestExpectation
    ) {
        self.started = started
        self.cancelled = cancelled
        self.presented = presented
    }
}

/// 持续让出执行器，直到 Router 对当前任务发出取消。
nonisolated private struct CancellationHandler: ContextCommandHandling {
    /// 跨执行隔离域使用的线程安全测试探针。
    let probe: CancellationProbe

    /// 在 Router 创建的同一个任务中观察取消状态。
    @concurrent func execute(_ command: RecordingCommand) async {
        probe.started.fulfill()
        while !Task.isCancelled {
            await Task.yield()
        }
        probe.cancelled.fulfill()
    }

    /// 已取消命令不应到达该主线程反馈出口。
    @MainActor func present(_ outcome: Void, requestID: UUID) {
        probe.presented.fulfill()
    }
}

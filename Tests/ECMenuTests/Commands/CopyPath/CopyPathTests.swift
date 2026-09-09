/**
 验证路径文本的顺序、目标存在性与剪贴板写入的完整业务结果。
 结合隔离文件和注入的 MainActor writer，覆盖写入失败及等待主执行器期间的取消。
 */

import Foundation
import XCTest
@testable import ECMenu

/// 验证拷贝路径的目标有效性、多选顺序和剪贴板正文。
final class CopyPathTests: XCTestCase {
    /// 多选路径应按 Finder 顺序逐行输出，且末尾没有额外换行。
    func testMultipleSelectionPreservesOrder() throws {
        let first = url("/test/Second Item")
        let second = url("/test/first.txt")
        let command = try command([first, second])

        let plan = try CopyPathRules.makePlan(
            for: command,
            existingURLs: [first, second]
        ).get()

        XCTAssertEqual(plan.itemURLs, [first, second])
        XCTAssertEqual(
            plan.pasteboardString,
            "/test/Second Item\n/test/first.txt"
        )
        XCTAssertFalse(plan.pasteboardString.hasSuffix("\n"))
    }

    /// 任一快照目标已经失效时不应把不完整的多选写入剪贴板。
    func testUnavailableSelectionFailsAsAWhole() throws {
        let existing = url("/test/existing")
        let missing = url("/test/missing")
        let command = try command([existing, missing])

        guard case .failure(.targetUnavailable) = CopyPathRules.makePlan(
            for: command,
            existingURLs: [existing]
        ) else {
            return XCTFail("A stale multi-selection must not produce partial clipboard text")
        }
    }

    /// 拷贝路径只关心 Finder 对象本身，失效符号链接仍应拥有可拷贝路径。
    @MainActor
    func testDanglingSymbolicLinkRemainsCopyable() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let link = fixture.appendingPathComponent("dangling-link")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.appendingPathComponent("missing-target")
        )

        var copied: String?
        let handler = CopyPathHandler(
            platform: CopyPathPlatform(existingURLs: CopyPathPlatform.system.existingURLs, writeString: {
                copied = $0
                return true
            }),
            present: { _, _ in XCTFail("Execution must not present feedback") }
        )
        let outcome = await handler.execute(try command([link]))
        XCTAssertEqual(outcome, .success(CopyPathSuccess(itemCount: 1)))
        XCTAssertEqual(copied, link.path)
    }

    @MainActor
    func testPasteboardFailureIsPartOfExecutionResult() async throws {
        let item = url("/test/item")
        var written: String?
        let handler = CopyPathHandler(
            platform: CopyPathPlatform(existingURLs: { _ in [item] }, writeString: {
                written = $0
                return false
            }),
            present: { _, _ in XCTFail("Execution must not present feedback") }
        )
        let result = await handler.execute(try command([item]))
        XCTAssertEqual(result, .failure(.pasteboardWriteFailed))
        XCTAssertEqual(written, item.path)
    }

    @MainActor
    func testUnavailableSelectionNeverWritesPasteboard() async throws {
        let item = url("/test/missing")
        let handler = CopyPathHandler(
            platform: CopyPathPlatform(existingURLs: { _ in [] }, writeString: { _ in
                XCTFail("An invalid selection must leave the clipboard untouched")
                return true
            }),
            present: { _, _ in XCTFail("Execution must not present feedback") }
        )
        let result = await handler.execute(try command([item]))
        XCTAssertEqual(result, .failure(.targetUnavailable))
    }

    @MainActor
    func testCancelledTaskDoesNotWritePasteboard() async throws {
        let item = url("/test/item")
        let command = try command([item])
        let handler = CopyPathHandler(
            platform: CopyPathPlatform(existingURLs: { _ in [item] }, writeString: { _ in
                XCTFail("A cancelled task must not write the clipboard")
                return true
            }),
            present: { _, _ in XCTFail("Execution must not present feedback") }
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await handler.execute(command)
        }
        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    /// 主执行器仍由测试占用时取消后台任务，排队的写入必须再次检查取消。
    @MainActor
    func testCancellationAfterReadingFactsPreventsMainActorWrite() async throws {
        let item = url("/test/item")
        let command = try command([item])
        let factsRead = DispatchSemaphore(value: 0)
        let handler = CopyPathHandler(
            platform: CopyPathPlatform(existingURLs: { _ in
                factsRead.signal()
                return [item]
            }, writeString: { _ in
                XCTFail("A task cancelled before its MainActor write must leave the clipboard untouched")
                return true
            }),
            present: { _, _ in XCTFail("Execution must not present feedback") }
        )
        let task = Task.detached { await handler.execute(command) }
        // 同步等待只阻塞这里占有的 MainActor；后台事实读取不依赖主执行器。
        XCTAssertEqual(factsRead.wait(timeout: .now() + 1), .success)
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    /// 创建标准化文件 URL。
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    /// 把测试 URL 构造成类型化拷贝命令。
    private func command(_ urls: [URL]) throws -> CopyPathCommand {
        try XCTUnwrap(
            CopyPathCommand(
                paths: urls.map { try XCTUnwrap(AbsoluteFilePath(url: $0)) }
            )
        )
    }
}

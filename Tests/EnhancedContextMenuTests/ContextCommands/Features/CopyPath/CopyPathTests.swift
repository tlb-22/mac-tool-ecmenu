import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证拷贝路径的 Finder 目标解析、多选顺序和剪贴板正文。
final class CopyPathTests: XCTestCase {
    /// 多选路径应按 Finder 顺序逐行输出，且末尾没有额外换行。
    func testMultipleSelectionPreservesOrder() throws {
        let first = url("/test/Second Item")
        let second = url("/test/first.txt")
        let snapshot = items([first, second])

        let plan = try CopyPathHandler.makePlan(
            for: snapshot,
            existingURLs: [first, second]
        ).get()

        XCTAssertEqual(plan.itemURLs, [first, second])
        XCTAssertEqual(
            plan.pasteboardString,
            "/test/Second Item\n/test/first.txt"
        )
        XCTAssertFalse(plan.pasteboardString.hasSuffix("\n"))
    }

    /// 空白处语义快照应直接携带已经解释完成的当前容器。
    func testContainerUsesSemanticDirectory() throws {
        let visibleDirectory = url("/test/parent")
        let snapshot = FinderContextSnapshot.container(
            path: visibleDirectory.path
        )

        let plan = try CopyPathHandler.makePlan(
            for: snapshot,
            existingURLs: [visibleDirectory]
        ).get()

        XCTAssertEqual(plan.itemURLs, [visibleDirectory])
    }

    /// 任一快照目标已经失效时不应把不完整的多选写入剪贴板。
    func testUnavailableSelectionFailsAsAWhole() {
        let existing = url("/test/existing")
        let missing = url("/test/missing")
        let snapshot = items([existing, missing])

        guard case .failure(.targetUnavailable) = CopyPathHandler.makePlan(
            for: snapshot,
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

        let outcome = await CopyPathHandler().execute(
            CopyPathCommand(
                finderContext: items([link])
            )
        )

        XCTAssertEqual(try outcome.get().itemURLs, [link])
    }

    /// 创建标准化文件 URL。
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    /// 构造测试使用的非空 Finder 项目语义。
    private func items(_ urls: [URL]) -> FinderContextSnapshot {
        guard let selection = FinderItemSelection(urls: urls) else {
            preconditionFailure("A test item selection cannot be empty")
        }
        return .items(selection: selection)
    }
}

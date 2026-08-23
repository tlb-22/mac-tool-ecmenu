import Darwin
import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证隐藏/显示的上下文范围、点号规则和真实文件属性写入。
final class VisibilityTests: XCTestCase {
    /// 只有明确的 Finder 选择可以形成可见性操作目标。
    func testOnlyItemSelectionsResolveTargets() {
        let parent = url("/test/parent")
        let first = url("/test/parent/first")
        let second = url("/test/parent/second")

        XCTAssertNil(
            VisibilityExecution.targetURLs(
                for: .container(path: parent.path)
            )
        )
        XCTAssertEqual(
            VisibilityExecution.targetURLs(for: items([first, second])),
            [first, second]
        )
        XCTAssertNil(
            VisibilityExecution.targetURLs(
                for: .sidebar(path: parent.path)
            )
        )
    }

    /// 执行端应拒绝空白处和侧边栏请求，防止迟到请求触发整层批量操作。
    func testContainerAndSidebarCommandsAreRejected() async {
        let snapshots: [FinderContextSnapshot] = [
            .container(path: "/test/parent"),
            .sidebar(path: "/test/parent"),
        ]

        for snapshot in snapshots {
            let hideOutcome = await HideItemsHandler().execute(
                HideItemsCommand(finderContext: snapshot)
            )
            let showOutcome = await ShowItemsHandler().execute(
                ShowItemsCommand(finderContext: snapshot)
            )

            XCTAssertEqual(hideOutcome, .targetUnavailable)
            XCTAssertEqual(showOutcome, .targetUnavailable)
        }
    }

    /// 点号名称必须保持原名并从属性写入计划中排除。
    func testDotItemsAreSkipped() {
        let ordinary = url("/test/ordinary")
        let dotItem = url("/test/.git")

        let plan = VisibilityExecution.makePlan(
            operation: .show,
            itemURLs: [ordinary, dotItem]
        )

        XCTAssertEqual(plan.itemURLs, [ordinary])
        XCTAssertEqual(plan.skippedDotItemCount, 1)
    }

    /// 真实批量执行只修改选中对象；符号链接不应影响目标文件。
    func testFileSystemExecutionIsNonRecursiveAndDoesNotFollowSymlinks() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let ordinary = fixture.appendingPathComponent("ordinary.txt")
        let directory = fixture.appendingPathComponent("folder", isDirectory: true)
        let nested = directory.appendingPathComponent("nested.txt")
        let link = fixture.appendingPathComponent("link")
        let dotItem = fixture.appendingPathComponent(".dot-item")
        FileManager.default.createFile(atPath: ordinary.path, contents: Data())
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        FileManager.default.createFile(atPath: nested.path, contents: Data())
        FileManager.default.createFile(atPath: dotItem.path, contents: Data())
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: nested
        )

        let hideOutcome = await HideItemsHandler().execute(
            HideItemsCommand(
                finderContext: items([
                    ordinary,
                    directory,
                    link,
                    dotItem,
                ])
            )
        )
        guard case .completed(let hideReport) = hideOutcome else {
            return XCTFail("A valid selection must produce a visibility report")
        }

        XCTAssertEqual(hideReport.succeededCount, 3)
        XCTAssertEqual(hideReport.skippedDotItemCount, 1)
        XCTAssertTrue(hideReport.issues.isEmpty)
        XCTAssertTrue(try isHidden(ordinary))
        XCTAssertTrue(try isHidden(directory))
        XCTAssertTrue(try isHidden(link))
        XCTAssertFalse(try isHidden(nested))

        var targetStat = stat()
        XCTAssertEqual(lstat(nested.path, &targetStat), 0)
        XCTAssertNotEqual(targetStat.st_flags & UInt32(UF_HIDDEN), UInt32(UF_HIDDEN))

        let showReport = VisibilityExecution.execute(
            VisibilityExecution.makePlan(
                operation: .show,
                itemURLs: [ordinary, directory, link, dotItem]
            )
        )
        XCTAssertEqual(showReport.succeededCount, 3)
        XCTAssertEqual(showReport.skippedDotItemCount, 1)
        XCTAssertFalse(try isHidden(ordinary))
        XCTAssertFalse(try isHidden(directory))
        XCTAssertFalse(try isHidden(link))
        XCTAssertTrue(try isHidden(dotItem))
    }

    /// 权限和只读错误必须与其他文件系统错误分开分类。
    func testErrorClassification() {
        let item = url("/test/item")

        XCTAssertEqual(
            VisibilityExecution.issue(
                for: POSIXError(.EACCES),
                itemURL: item
            ).kind,
            .permissionDenied
        )
        XCTAssertEqual(
            VisibilityExecution.issue(
                for: POSIXError(.EROFS),
                itemURL: item
            ).kind,
            .readOnlyFileSystem
        )
        XCTAssertEqual(
            VisibilityExecution.issue(
                for: POSIXError(.ENOENT),
                itemURL: item
            ).kind,
            .fileSystem
        )
    }

    /// 读取对象当前的 macOS 隐藏状态。
    private func isHidden(_ url: URL) throws -> Bool {
        try XCTUnwrap(
            url.resourceValues(forKeys: [.isHiddenKey]).isHidden
        )
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

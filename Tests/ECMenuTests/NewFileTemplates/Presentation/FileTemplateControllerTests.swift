/**
 验证模板页面状态协调器的共享加载、提交快照与错误恢复。
 通过隔离库及可控操作检查读取失败、写入失败和提交后清理问题对应的界面状态。
 */

import Combine
import Darwin
import Foundation
import XCTest
@testable import ECMenu

@MainActor
final class FileTemplateControllerTests: XCTestCase {
    /// 启动和窗口同时请求加载时共享一次发布，失败状态不会被伪装为空模板库。
    func testConcurrentInitialLoadPublishesOneCommittedSnapshot() async throws {
        let directory = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = FileTemplateLibrary(rootURL: directory.appendingPathComponent("Library"))
        var changes: [[FileTemplate]] = []
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) {
            changes.append($0)
        })
        XCTAssertNil(controller.templates)

        async let first: Void = controller.loadIfNeeded()
        async let second: Void = controller.loadIfNeeded()
        _ = await (first, second)

        let committed = try await library.load().templates
        XCTAssertEqual(controller.templates, committed)
        XCTAssertEqual(changes, [committed])
    }

    /// 索引读取失败保持明确错误，用户修复后可重试恢复原有模板身份。
    func testUnreadableIndexRemainsFailureUntilExplicitRetry() async throws {
        let directory = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let libraryURL = directory.appendingPathComponent("Library")
        let initializedLibrary = FileTemplateLibrary(rootURL: libraryURL)
        let original = try await initializedLibrary.load().templates
        let indexURL = libraryURL.appendingPathComponent("index.json")
        let originalData = try Data(contentsOf: indexURL)
        try Data("not JSON".utf8).write(to: indexURL)
        let library = FileTemplateLibrary(rootURL: libraryURL)
        var changes: [[FileTemplate]] = []
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) {
            changes.append($0)
        })

        await controller.loadIfNeeded()
        guard case .failed(let message) = controller.state else {
            return XCTFail("Invalid persisted data must remain a visible load failure")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNil(controller.templates)
        XCTAssertTrue(changes.isEmpty)

        try originalData.write(to: indexURL)
        await controller.loadIfNeeded()
        XCTAssertNil(controller.templates)
        await controller.reload()
        XCTAssertEqual(controller.templates, original)
        XCTAssertEqual(changes, [original])
    }

    /// 写盘失败保持已提交列表挂载，原地编辑控件不会经历 loading 重建。
    func testNameWriteFailureKeepsReadySnapshotThroughoutRecovery() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        var changes: [[FileTemplate]] = []
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) { changes.append($0) })
        await controller.loadIfNeeded()
        let original = try XCTUnwrap(controller.templates)
        let template = try XCTUnwrap(original.first)
        var states: [FileTemplatePageState] = []
        let subscription = controller.$state.sink { states.append($0) }
        defer { subscription.cancel() }

        // 非空目录阻止索引的原子替换，不依赖当前用户的 POSIX 写权限。
        try FileManager.default.removeItem(at: fixture.indexURL)
        try FileManager.default.createDirectory(at: fixture.indexURL, withIntermediateDirectories: false)
        try Data("occupied".utf8).write(to: fixture.indexURL.appendingPathComponent("blocker"))

        do {
            try await controller.updateName(for: template.id, field: .displayName, value: "Notes")
            XCTFail("An index write failure must be reported to the name editor")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.saveIndex, let url, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url.path, fixture.indexURL.path)
        }

        XCTAssertFalse(states.isEmpty)
        XCTAssertTrue(states.allSatisfy { $0 == .ready(original) })
        XCTAssertEqual(controller.state, .ready(original))
        XCTAssertEqual(controller.templates, original)
        XCTAssertFalse(controller.isUpdating)
        XCTAssertEqual(changes, [original])
    }

    /// 名称重复按 ID 更新正确行，失败导入保持有效快照并向界面报告错误。
    func testMutationSnapshotsKeepIdentityAndExposeImportFailure() async throws {
        let directory = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = FileTemplateLibrary(rootURL: directory.appendingPathComponent("Library"))
        var changes: [[FileTemplate]] = []
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) {
            changes.append($0)
        })
        await controller.loadIfNeeded()
        let original = try XCTUnwrap(controller.templates?.first)
        let source = directory.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: source)

        try await controller.importFile(at: source)
        let imported = try XCTUnwrap(controller.templates?.last)
        XCTAssertNotEqual(imported.id, original.id)
        let edited = try FileTemplate(
            id: imported.id,
            displayName: original.displayName,
            defaultFileName: original.defaultFileName
        )
        try await controller.updateTemplate(edited)
        XCTAssertEqual(controller.templates, [original, edited])

        do {
            try await controller.importFile(at: directory)
            XCTFail("A directory must not become a file template")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(controller.templates, [original, edited])
        XCTAssertFalse(controller.isUpdating)
        XCTAssertEqual(changes.last, [original, edited])

        try await controller.removeTemplate(id: edited.id)
        XCTAssertEqual(controller.templates, [original])
        let persisted = try await library.load().templates
        XCTAssertEqual(controller.templates, persisted)
        XCTAssertEqual(try Data(contentsOf: source), Data("notes".utf8))
    }

    func testCommittedDeletionPublishesRemovedRowBeforeReportingCleanupIssue() async throws {
        let fixture = try FileTemplateLibraryFixture()
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        var changes: [[FileTemplate]] = []
        let operations = FileTemplateOperations(library: library) { changes.append($0) }
        let controller = FileTemplateController(operations: operations)
        await controller.loadIfNeeded()
        let template = try XCTUnwrap(controller.templates?.first)
        let url = try await operations.fileURL(for: template.id)
        defer {
            _ = chflags(url.path, 0)
            fixture.remove()
        }
        XCTAssertEqual(chflags(url.path, UInt32(UF_IMMUTABLE)), 0)

        do {
            try await controller.removeTemplate(id: template.id)
            XCTFail("Deletion cleanup failure must remain visible")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.removeContent, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(controller.state, .ready([]))
            XCTAssertEqual(changes, [[template], []])
        }
        XCTAssertFalse(controller.isUpdating)
        let persisted = try await library.load().templates
        XCTAssertEqual(persisted, [])
    }

    func testCommittedReplacementKeepsSuccessfulUIResultWhenCleanupFails() async throws {
        let fixture = try FileTemplateLibraryFixture()
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        var changes: [[FileTemplate]] = []
        let operations = FileTemplateOperations(library: library) { changes.append($0) }
        let controller = FileTemplateController(operations: operations)
        await controller.loadIfNeeded()
        let template = try XCTUnwrap(controller.templates?.first)
        let url = try await operations.fileURL(for: template.id)
        defer {
            _ = chflags(url.path, 0)
            fixture.remove()
        }
        XCTAssertEqual(chflags(url.path, UInt32(UF_IMMUTABLE)), 0)
        let replacement = try fixture.source(named: "replacement.md", data: Data("replacement".utf8))

        try await controller.replaceTemplate(id: template.id, at: replacement)

        XCTAssertEqual(controller.state, .ready([template]))
        XCTAssertEqual(changes, [[template], [template]])
        XCTAssertFalse(controller.isUpdating)
        let content = try await operations.content(for: template.id)
        XCTAssertEqual(content.data, Data("replacement".utf8))
    }
}

/**
 验证模板排序从页面提交到索引保存和菜单发布的完整链路。
 在隔离模板库检查稳定身份、最新元数据与内容保留、无变化不提交及写入失败恢复。
 */

import Combine
import Foundation
import XCTest
@testable import ECMenu

@MainActor
final class FileTemplateOrderingTests: XCTestCase {
    func testMovesPersistCurrentRecordsAndPublishOnlyChangedOrder() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let markdown = try fixture.source(named: "notes.md", data: Data("# Notes".utf8))
        let binary = try fixture.source(named: "sample.bin", data: Data([0, 255, 10, 128]))
        _ = try await library.importFile(at: markdown)
        _ = try await library.importFile(at: binary)
        var changes: [[FileTemplate]] = []
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) {
            changes.append($0)
        })
        await controller.loadIfNeeded()
        let initial = try XCTUnwrap(controller.templates)

        // 排序只传身份与目标，从库的最新记录移动，不能用页面旧快照覆盖已提交字段。
        let updated = try await library.updateName(
            for: initial[2].id, field: .displayName, value: "Current name"
        ).templates
        let originalRecords = try JSONDecoder().decode(
            FileTemplateIndex.self, from: Data(contentsOf: fixture.indexURL)
        ).templates

        try await controller.moveTemplate(id: initial[2].id, before: initial[0].id)
        let firstOrder = [updated[2], updated[0], updated[1]]
        XCTAssertEqual(controller.templates, firstOrder)
        XCTAssertEqual(changes, [initial, firstOrder])

        try await controller.moveTemplate(id: initial[2].id, before: nil)
        XCTAssertEqual(controller.templates, updated)
        XCTAssertEqual(changes, [initial, firstOrder, updated])

        try await controller.moveTemplate(id: initial[0].id, before: initial[2].id)
        let finalOrder = [updated[1], updated[0], updated[2]]
        XCTAssertEqual(controller.templates, finalOrder)
        XCTAssertEqual(changes, [initial, firstOrder, updated, finalOrder])
        XCTAssertFalse(controller.isUpdating)

        let restarted = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let restored = try await restarted.load().templates
        XCTAssertEqual(restored, finalOrder)
        let finalRecords = try JSONDecoder().decode(
            FileTemplateIndex.self, from: Data(contentsOf: fixture.indexURL)
        ).templates
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: finalRecords.map { ($0.template.id, $0) }),
            Dictionary(uniqueKeysWithValues: originalRecords.map { ($0.template.id, $0) })
        )
        let markdownContent = try await restarted.content(for: initial[1].id)
        let binaryContent = try await restarted.content(for: initial[2].id)
        XCTAssertEqual(markdownContent.data, Data("# Notes".utf8))
        XCTAssertEqual(binaryContent.data, Data([0, 255, 10, 128]))

        // 阻断真实写入后，无变化的 drop 仍应完成，且不重新发布或替换页面快照。
        try FileManager.default.removeItem(at: fixture.indexURL)
        try FileManager.default.createDirectory(at: fixture.indexURL, withIntermediateDirectories: false)
        try Data("occupied".utf8).write(to: fixture.indexURL.appendingPathComponent("blocker"))
        var states: [FileTemplatePageState] = []
        let subscription = controller.$state.sink { states.append($0) }
        defer { subscription.cancel() }
        try await controller.moveTemplate(id: initial[1].id, before: initial[0].id)
        try await controller.moveTemplate(id: initial[0].id, before: initial[0].id)
        try await controller.moveTemplate(id: initial[2].id, before: nil)
        XCTAssertEqual(states, [.ready(finalOrder)])
        XCTAssertEqual(changes, [initial, firstOrder, updated, finalOrder])
        XCTAssertFalse(controller.isUpdating)
    }

    func testOrderWriteFailureKeepsCommittedSnapshotAndCanBeRetried() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let source = try fixture.source(named: "notes.md", data: Data("notes".utf8))
        let original = try await library.importFile(at: source).templates
        var changes: [[FileTemplate]] = []
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) {
            changes.append($0)
        })
        await controller.loadIfNeeded()
        let savedIndex = try Data(contentsOf: fixture.indexURL)
        try FileManager.default.removeItem(at: fixture.indexURL)
        try FileManager.default.createDirectory(at: fixture.indexURL, withIntermediateDirectories: false)
        try Data("occupied".utf8).write(to: fixture.indexURL.appendingPathComponent("blocker"))

        do {
            try await controller.moveTemplate(id: original[1].id, before: original[0].id)
            XCTFail("An index write failure must be reported without applying the requested order")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.saveIndex, let url, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url.path, fixture.indexURL.path)
        }
        let retained = try await library.load().templates
        XCTAssertEqual(retained, original)
        XCTAssertEqual(controller.state, .ready(original))
        XCTAssertEqual(changes, [original])
        XCTAssertFalse(controller.isUpdating)

        try FileManager.default.removeItem(at: fixture.indexURL)
        try savedIndex.write(to: fixture.indexURL)
        try await controller.moveTemplate(id: original[1].id, before: original[0].id)
        let reordered = [original[1], original[0]]
        XCTAssertEqual(controller.templates, reordered)
        XCTAssertEqual(changes, [original, reordered])
        let restored = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertEqual(restored, reordered)
    }
}

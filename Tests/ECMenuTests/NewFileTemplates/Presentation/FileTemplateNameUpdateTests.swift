/**
 验证名称保存按模板身份定位，并保留另一个字段最近提交的值。
 使用隔离模板库检查重名、无效输入和目标删除时的更新及发布边界。
 */

import Foundation
import XCTest
@testable import ECMenu

@MainActor
final class FileTemplateNameUpdateTests: XCTestCase {
    /// 后编辑的字段必须保留另一字段最近一次已提交的值。
    func testUpdatingEachNamePreservesTheOtherLatestCommittedName() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        var changes: [[FileTemplate]] = []
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) { changes.append($0) })
        await controller.loadIfNeeded()
        let original = try XCTUnwrap(controller.templates?.first)
        let fileURL = try await library.fileURL(for: original.id)

        try await controller.updateName(for: original.id, field: .defaultFileName, value: "notes.md")
        try await controller.updateName(for: original.id, field: .displayName, value: "Notes")
        let expected = try FileTemplate(id: original.id, displayName: "Notes", defaultFileName: "notes.md")
        XCTAssertEqual(controller.templates, [expected])
        XCTAssertEqual(changes.count, 3)
        let persisted = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertEqual(persisted, [expected])
        let unchangedFileURL = try await library.fileURL(for: original.id)
        XCTAssertEqual(unchangedFileURL, fileURL)

        try await controller.updateName(for: original.id, field: .defaultFileName, value: "latest.txt")
        XCTAssertEqual(controller.templates?.first?.displayName, "Notes")
        XCTAssertEqual(controller.templates?.first?.defaultFileName, "latest.txt")
    }

    func testDuplicateDisplayNamesAreUpdatedByIdentityAndInvalidNamesAreNotPublished() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let source = try fixture.source(named: "second.txt", data: Data("second".utf8))
        _ = try await library.importFile(at: source)
        var changes: [[FileTemplate]] = []
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) { changes.append($0) })
        await controller.loadIfNeeded()
        let initial = try XCTUnwrap(controller.templates)
        let first = initial[0]
        let second = initial[1]

        try await controller.updateName(for: second.id, field: .displayName, value: first.displayName)
        try await controller.updateName(for: second.id, field: .defaultFileName, value: "second-copy.txt")
        let updatedSecond = try FileTemplate(id: second.id, displayName: first.displayName, defaultFileName: "second-copy.txt")
        XCTAssertEqual(controller.templates, [first, updatedSecond])
        let publishedCount = changes.count
        do {
            try await controller.updateName(for: second.id, field: .defaultFileName, value: "folder/name.txt")
            XCTFail("A folder path must not become a default file name")
        } catch {
            XCTAssertEqual(error as? FileTemplateValidationError, .invalidDefaultFileName)
        }
        XCTAssertEqual(controller.templates, [first, updatedSecond])
        XCTAssertEqual(changes.count, publishedCount)
        XCTAssertFalse(controller.isUpdating)
        let persisted = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertEqual(persisted, [first, updatedSecond])
    }

    func testDeletedNameTargetDoesNotUpdateAnotherTemplateWithTheSameName() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let source = try fixture.source(named: "second.txt", data: Data())
        let initial = try await library.importFile(at: source).templates
        let sameNamed = try FileTemplate(id: initial[1].id, displayName: initial[0].displayName, defaultFileName: initial[0].defaultFileName)
        _ = try await library.update(sameNamed)
        let controller = FileTemplateController(operations: FileTemplateOperations(library: library) { _ in })
        await controller.loadIfNeeded()
        try await controller.removeTemplate(id: initial[0].id)

        do {
            try await controller.updateName(for: initial[0].id, field: .displayName, value: "Edited")
            XCTFail("A deleted identity cannot resolve to another template with the same name")
        } catch {
            XCTAssertEqual(error as? FileTemplateLibraryError, .templateNotFound(initial[0].id))
        }
        XCTAssertEqual(controller.templates, [sameNamed])
        XCTAssertFalse(controller.isUpdating)
    }
}

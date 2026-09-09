/**
 验证模板操作层在初始化、管理读取和内容打开时发布模板清单变化的时机。
 使用隔离模板库与注入回调，检查缓存读取、缺失身份及已保存内容的打开。
 */

import Foundation
import XCTest
@testable import ECMenu

@MainActor
final class FileTemplateOperationsTests: XCTestCase {
    func testInitializationPublishesOnceAndOrdinaryCachedReadsDoNotPublish() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        var changes: [[FileTemplate]] = []
        let operations = FileTemplateOperations(library: library) { changes.append($0) }

        let initial = try await operations.load()
        let template = try XCTUnwrap(initial.first)
        XCTAssertEqual(changes, [initial])
        _ = try await operations.load()
        _ = try await operations.content(for: template.id)
        _ = try await operations.fileURL(for: template.id)
        XCTAssertEqual(changes, [initial])

        let cached = try await library.load()
        XCTAssertEqual(cached.origin, .cached)
        let restored = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
        XCTAssertEqual(restored.origin, .restored)
        XCTAssertEqual(restored.templates, initial)
    }

    func testManagementReadsPublishAvailabilityWithoutDuplicatingInitialization() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        var changes: [[FileTemplate]] = []
        let operations = FileTemplateOperations(library: FileTemplateLibrary(rootURL: fixture.libraryURL)) {
            changes.append($0)
        }

        let initial = try await operations.loadForManagement()
        XCTAssertEqual(changes, [initial])
        _ = try await operations.loadForManagement()
        XCTAssertEqual(changes, [initial, initial])

        var restoredChanges: [[FileTemplate]] = []
        let restored = FileTemplateOperations(library: FileTemplateLibrary(rootURL: fixture.libraryURL)) {
            restoredChanges.append($0)
        }
        _ = try await restored.load()
        XCTAssertTrue(restoredChanges.isEmpty)
        _ = try await restored.loadForManagement()
        XCTAssertEqual(restoredChanges, [initial])
    }

    func testContentRequestPublishesInitializationBeforeReportingMissingIdentity() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        var changes: [[FileTemplate]] = []
        let operations = FileTemplateOperations(library: FileTemplateLibrary(rootURL: fixture.libraryURL)) {
            changes.append($0)
        }
        let missing = FileTemplateID()

        do {
            _ = try await operations.content(for: missing)
            XCTFail("A missing identity must remain a template failure")
        } catch {
            XCTAssertEqual(error as? FileTemplateLibraryError, .templateNotFound(missing))
        }

        XCTAssertEqual(changes.count, 1)
        let template = try XCTUnwrap(changes.first?.first)
        let content = try await operations.content(for: template.id)
        XCTAssertEqual(content.data, Data())
        XCTAssertEqual(changes.count, 1)
    }

    func testOpeningRestoresSavedTemplateWithoutPublishingChanges() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let bytes = Data("notes".utf8)
        let source = try fixture.source(named: "notes.md", data: bytes)
        let savedLibrary = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let imported = try await savedLibrary.importFile(at: source)
        let template = try XCTUnwrap(imported.templates.last)
        let savedURL = try await savedLibrary.fileURL(for: template.id)
        var changes: [[FileTemplate]] = []
        var opened: [URL] = []
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let operations = FileTemplateOperations(
            library: library,
            openFile: { url in
                XCTAssertTrue(changes.isEmpty)
                opened.append(url)
            },
            didChange: { changes.append($0) }
        )

        try await operations.openTemplate(id: template.id)

        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(opened, [savedURL])
        let content = try await operations.content(for: template.id)
        XCTAssertEqual(content.data, bytes)
        XCTAssertTrue(changes.isEmpty)
        let cached = try await library.load()
        XCTAssertEqual(cached.origin, .cached)
    }
}

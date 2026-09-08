/**
 验证模板库初始化、导入、删除、缓存与索引提交的一致性。
 在隔离目录检查二进制副本、命名、无效文件拒绝、孤儿清理及提交后的清理问题。
 */

import Darwin
import Foundation
import XCTest
@testable import ECMenu

final class FileTemplateLibraryTests: XCTestCase {
    func testInitialTemplateIsSavedOnceAndEmptyLibrarySurvivesRestart() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let template = try XCTUnwrap(initial.first)
        XCTAssertEqual(initial.count, 1)
        XCTAssertEqual(template.displayName, "TXT")
        XCTAssertEqual(template.defaultFileName, "untitled.txt")
        let content = try await library.content(for: template.id)
        XCTAssertEqual(content.data, Data())
        let reloaded = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertEqual(reloaded, initial)

        let index = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.indexURL)) as? [String: Any])
        XCTAssertEqual(Set(index.keys), ["schemaVersion", "templates"])
        XCTAssertEqual(index["schemaVersion"] as? Int, 2)
        let records = try XCTUnwrap(index["templates"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(records.first).keys), ["template", "file"])
        let contentURL = try fixture.contentURL(for: template.id)

        let deleted = try await library.remove(id: template.id).templates
        XCTAssertTrue(deleted.isEmpty)
        let restarted = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertTrue(restarted.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: contentURL.path))
    }

    func testImportPreservesBinaryContentsIndependentlyOfSourceAndNames() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let original = Data([0, 255, 10, 0, 128, 127])
        let source = try fixture.source(named: "sample.bin", data: original)
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let imported = try await library.importFile(at: source).templates
        let template = try XCTUnwrap(imported.last)
        XCTAssertEqual(template.displayName, "BIN")
        XCTAssertEqual(template.defaultFileName, "untitled.bin")
        try Data("changed".utf8).write(to: source)
        try FileManager.default.removeItem(at: source)

        let edited = try FileTemplate(id: template.id, displayName: "配置", defaultFileName: "sample.dat")
        let updated = try await library.update(edited).templates
        XCTAssertEqual(updated.last, edited)
        let restarted = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let content = try await restarted.content(for: template.id)
        XCTAssertEqual(content.template, edited)
        XCTAssertEqual(content.data, original)
        let contentURL = try await restarted.fileURL(for: template.id)
        XCTAssertEqual(contentURL.lastPathComponent, "sample.bin")
        XCTAssertNotEqual(contentURL.deletingLastPathComponent().lastPathComponent, template.id.rawValue.uuidString)
    }

    func testAutomaticNamesFillFirstAvailableSuffixAndManualNamesMayRepeat() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let source = try fixture.source(named: "notes.txt", data: Data("note".utf8))
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let second = try await library.importFile(at: source).templates
        XCTAssertEqual(second.map(\.displayName), ["TXT", "TXT 2"])
        let third = try await library.importFile(at: source).templates
        XCTAssertEqual(third.map(\.displayName), ["TXT", "TXT 2", "TXT 3"])

        let renamed = try FileTemplate(id: third[1].id, displayName: "TXT 3", defaultFileName: "untitled.txt")
        let manual = try await library.update(renamed).templates
        XCTAssertEqual(manual.map(\.displayName), ["TXT", "TXT 3", "TXT 3"])
        let fourth = try await library.importFile(at: source).templates
        XCTAssertEqual(fourth.map(\.displayName), ["TXT", "TXT 3", "TXT 3", "TXT 2"])
        XCTAssertEqual(Set(fourth.map(\.id)).count, 4)
        XCTAssertEqual(Set(fourth.map(\.defaultFileName)), ["untitled.txt"])

        let noExtension = try fixture.source(named: "LICENSE", data: Data("license".utf8))
        let fifth = try await library.importFile(at: noExtension).templates
        XCTAssertEqual(fifth.last?.displayName, "LICENSE")
        XCTAssertEqual(fifth.last?.defaultFileName, "untitled")
    }

    func testRemovingTemplatePreservesSourceAndOtherTemplateWithSameNames() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let bytes = Data("sample".utf8)
        let source = try fixture.source(named: "sample.txt", data: bytes)
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let templates = try await library.importFile(at: source).templates
        let original = templates[0]
        let imported = templates[1]
        _ = try await library.update(FileTemplate(id: imported.id, displayName: original.displayName, defaultFileName: original.defaultFileName))
        let remaining = try await library.remove(id: original.id).templates
        XCTAssertEqual(remaining.map(\.id), [imported.id])
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let content = try await library.content(for: imported.id)
        XCTAssertEqual(content.data, bytes)
        do {
            _ = try await library.content(for: original.id)
            XCTFail("A deleted identity must not resolve to another identically named template")
        } catch {
            XCTAssertEqual(error as? FileTemplateLibraryError, .templateNotFound(original.id))
        }
    }

    func testDirectoryPackageSymlinkAndSpecialFileCannotBeImported() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let fileManager = FileManager.default
        let directory = fixture.rootURL.appendingPathComponent("folder")
        let package = fixture.rootURL.appendingPathComponent("Sample.app")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        let source = try fixture.source(named: "source.txt", data: Data())
        let symlink = fixture.rootURL.appendingPathComponent("link.txt")
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: source)
        let fifo = fixture.rootURL.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        for url in [directory, package, symlink, fifo] {
            do {
                _ = try await library.importFile(at: url)
                XCTFail("Only regular files can be imported: \(url.lastPathComponent)")
            } catch {
                XCTAssertEqual(error as? FileTemplateLibraryError, .unsupportedFile(url))
            }
        }
        let unchanged = try await library.load().templates
        XCTAssertEqual(unchanged, initial)
    }

    func testCorruptAndUnsupportedIndexesAreNotReplacedOrCleaned() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let orphan = fixture.filesURL.appendingPathComponent(UUID().uuidString)
        try Data("unreferenced".utf8).write(to: orphan)
        let originalURL = try fixture.contentURL(for: initial[0].id)
        let corrupt = Data("{invalid json".utf8)
        let missingFields = Data(#"{"schemaVersion":1}"#.utf8)
        let future = Data(#"{"schemaVersion":3,"templates":[]}"#.utf8)
        let duplicateID = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "templates": [initial[0], initial[0]].map { [
                "id": $0.id.rawValue.uuidString,
                "displayName": $0.displayName,
                "defaultFileName": $0.defaultFileName,
            ] },
        ])
        for data in [corrupt, missingFields, future, duplicateID] {
            try data.write(to: fixture.indexURL)
            do {
                _ = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
                XCTFail("An invalid index must not initialize an empty replacement")
            } catch let error as FileTemplateLibraryError {
                if data == future {
                    XCTAssertEqual(error, .unsupportedSchema(3))
                } else if case .invalidIndex = error {
                    // 当前索引损坏在解码边界明确分类。
                } else {
                    XCTFail("Unexpected index error: \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: fixture.indexURL), data)
            XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        }
    }

    func testMissingContentFailsWithoutSubstitutingAnEmptyFile() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let templates = try await library.load().templates
        let template = templates[0]
        try FileManager.default.removeItem(at: fixture.contentURL(for: template.id))
        let loaded = try await library.load().templates
        XCTAssertEqual(loaded, templates)
        do {
            _ = try await library.content(for: template.id)
            XCTFail("Missing content must fail, even for an originally empty TXT")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.readContent, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMissingIndexInAnExistingLibraryIsNotReinitialized() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let contentDirectoryName = try fixture.contentURL(for: initial[0].id).deletingLastPathComponent().lastPathComponent
        try FileManager.default.removeItem(at: fixture.indexURL)
        let cached = try await library.load().templates
        XCTAssertEqual(cached, initial)
        do {
            _ = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
            XCTFail("An existing library without its index must fail to load")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.readIndex, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.indexURL.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path)
        XCTAssertEqual(files, [contentDirectoryName])
    }

    func testLoadCleansOnlyUnreferencedFiles() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let orphan = fixture.filesURL.appendingPathComponent(UUID().uuidString)
        try Data("interrupted import".utf8).write(to: orphan)
        let cached = try await library.load().templates
        XCTAssertEqual(cached, initial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        let loaded = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertEqual(loaded, initial)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try fixture.contentURL(for: initial[0].id).path))
    }

    func testIndexWriteFailureDoesNotPublishImportedTemplateAndRetryCleansOrphan() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let source = try fixture.source(named: "sample.txt", data: Data("new".utf8))
        let savedIndex = try Data(contentsOf: fixture.indexURL)
        let contentDirectoryName = try fixture.contentURL(for: initial[0].id).deletingLastPathComponent().lastPathComponent
        try FileManager.default.removeItem(at: fixture.indexURL)
        try FileManager.default.createDirectory(at: fixture.indexURL, withIntermediateDirectories: false)
        do {
            _ = try await library.importFile(at: source)
            XCTFail("A failed index commit must fail the import")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.saveIndex, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let original = try await library.content(for: initial[0].id)
        XCTAssertEqual(original.template, initial[0])
        XCTAssertEqual(original.data, Data())
        try FileManager.default.removeItem(at: fixture.indexURL)
        try savedIndex.write(to: fixture.indexURL)
        let loaded = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertEqual(loaded, initial)
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path)
        XCTAssertEqual(files, [contentDirectoryName])
    }

    func testRemovalReportsCleanupFailureWhileKeepingCommittedSnapshot() async throws {
        let fixture = try FileTemplateLibraryFixture()
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let contentURL = try fixture.contentURL(for: initial[0].id)
        defer {
            _ = chflags(contentURL.path, 0)
            fixture.remove()
        }
        XCTAssertEqual(chflags(contentURL.path, UInt32(UF_IMMUTABLE)), 0)
        let result = try await library.remove(id: initial[0].id)
        guard case .committedWithCleanupIssue(let templates, let issue) = result else {
            return XCTFail("A deletion must return its committed snapshot with any cleanup issue")
        }
        XCTAssertTrue(templates.isEmpty)
        XCTAssertEqual(issue.url, contentURL.deletingLastPathComponent())
        let committed = try await library.load().templates
        XCTAssertTrue(committed.isEmpty)
        let restarted = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertTrue(restarted.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: contentURL.path))
        XCTAssertEqual(chflags(contentURL.path, 0), 0)
        let cleaned = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load().templates
        XCTAssertTrue(cleaned.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: contentURL.path))
    }
}

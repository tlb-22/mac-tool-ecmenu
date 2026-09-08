/**
 验证替换模板内容保留菜单身份，同时隔离外部编辑的旧文件路径。
 覆盖索引提交失败、提交后清理失败和打开前文件校验，检查可见结果与磁盘内容。
 */

import Darwin
import Foundation
import XCTest
@testable import ECMenu

final class FileTemplateReplacementTests: XCTestCase {
    func testReplacementPreservesIdentityNamesAndOrderAndCopiesOriginalFileName() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let template = try FileTemplate(id: initial[0].id, displayName: "My Template", defaultFileName: "custom.txt")
        _ = try await library.update(template)
        let otherSource = try fixture.source(named: "other.txt", data: Data("other".utf8))
        let before = try await library.importFile(at: otherSource).templates
        let oldURL = try await library.fileURL(for: template.id)
        let bytes = Data([0, 255, 127, 128])
        let source = try fixture.source(named: "Original Template.bin", data: bytes)

        let after = try await library.replaceFile(for: template.id, at: source).templates
        XCTAssertEqual(after, before)
        let newURL = try await library.fileURL(for: template.id)
        XCTAssertEqual(newURL.lastPathComponent, "Original Template.bin")
        XCTAssertNotEqual(newURL.deletingLastPathComponent(), oldURL.deletingLastPathComponent())
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        try Data("changed source".utf8).write(to: source)
        try FileManager.default.removeItem(at: source)

        let restarted = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let persisted = try await restarted.content(for: template.id)
        XCTAssertEqual(persisted.template, template)
        XCTAssertEqual(persisted.data, bytes)
        let persistedURL = try await restarted.fileURL(for: template.id)
        XCTAssertEqual(persistedURL, newURL)
    }

    func testExternalEditingIsReadFreshAndLateSaveToOldFileCannotChangeReplacement() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let id = initial[0].id
        let originalURL = try await library.fileURL(for: id)
        let edited = Data("edited in default application".utf8)
        try edited.write(to: originalURL, options: .atomic)
        let editedContent = try await library.content(for: id)
        XCTAssertEqual(editedContent.data, edited)

        let replacementBytes = Data("replacement".utf8)
        let source = try fixture.source(named: "LICENSE", data: replacementBytes)
        _ = try await library.replaceFile(for: id, at: source)
        let currentURL = try await library.fileURL(for: id)
        XCTAssertEqual(currentURL.lastPathComponent, "LICENSE")
        try FileManager.default.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: false)
        try Data("late save from old editor".utf8).write(to: originalURL)
        let current = try await library.content(for: id)
        XCTAssertEqual(current.data, replacementBytes)
        XCTAssertEqual(current.template.defaultFileName, "untitled.txt")

        let restarted = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let reloaded = try await restarted.content(for: id)
        XCTAssertEqual(reloaded.data, replacementBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentURL.path))
    }

    func testFailedCommitKeepsMetadataAndContentAndCleansUncommittedCopy() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let id = initial[0].id
        let originalURL = try await library.fileURL(for: id)
        let savedIndex = try Data(contentsOf: fixture.indexURL)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path)
        let source = try fixture.source(named: "new.md", data: Data("new content".utf8))
        try FileManager.default.removeItem(at: fixture.indexURL)
        try FileManager.default.createDirectory(at: fixture.indexURL, withIntermediateDirectories: false)

        do {
            _ = try await library.replaceFile(for: id, at: source)
            XCTFail("A failed index commit must not publish the replacement")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.saveIndex, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let unchanged = try await library.load().templates
        XCTAssertEqual(unchanged, initial)
        let content = try await library.content(for: id)
        XCTAssertEqual(content.data, Data())
        let unchangedURL = try await library.fileURL(for: id)
        XCTAssertEqual(unchangedURL, originalURL)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path), filesBefore)

        try FileManager.default.removeItem(at: fixture.indexURL)
        try savedIndex.write(to: fixture.indexURL)
        let retried = try await library.replaceFile(for: id, at: source).templates
        XCTAssertEqual(retried, initial)
        let replacement = try await library.content(for: id)
        XCTAssertEqual(replacement.data, Data("new content".utf8))
    }

    func testInvalidReplacementDoesNotChangeLibraryOrCopyDirectories() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let directory = fixture.rootURL.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let source = try fixture.source(named: "sample.txt", data: Data())
        let symlink = fixture.rootURL.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        let fifo = fixture.rootURL.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let savedIndex = try Data(contentsOf: fixture.indexURL)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path)
        for url in [directory, symlink, fifo] {
            do {
                _ = try await library.replaceFile(for: initial[0].id, at: url)
                XCTFail("Replacement must accept only ordinary files")
            } catch {
                XCTAssertEqual(error as? FileTemplateLibraryError, .unsupportedFile(url))
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.indexURL), savedIndex)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path), filesBefore)
    }

    func testReplacingSameNamedTemplateUsesIdentityAndDeletedIdentityDoesNotCopy() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let source = try fixture.source(named: "other.txt", data: Data("other".utf8))
        let imported = try await library.importFile(at: source).templates
        let first = imported[0]
        let second = try FileTemplate(id: imported[1].id, displayName: first.displayName, defaultFileName: first.defaultFileName)
        _ = try await library.update(second)
        let replacement = try fixture.source(named: "new.bin", data: Data([255, 0]))
        _ = try await library.replaceFile(for: second.id, at: replacement)
        let firstContent = try await library.content(for: first.id)
        let secondContent = try await library.content(for: second.id)
        XCTAssertEqual(firstContent.data, Data())
        XCTAssertEqual(secondContent.data, Data([255, 0]))
        _ = try await library.remove(id: second.id)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path)
        do {
            _ = try await library.replaceFile(for: second.id, at: replacement)
            XCTFail("A deleted template must not resolve to another with the same names")
        } catch {
            XCTAssertEqual(error as? FileTemplateLibraryError, .templateNotFound(second.id))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path), filesBefore)
    }

    func testCommittedReplacementSucceedsWhenOldCopyCannotBeCleaned() async throws {
        let fixture = try FileTemplateLibraryFixture()
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let oldURL = try await library.fileURL(for: initial[0].id)
        defer {
            _ = chflags(oldURL.path, 0)
            fixture.remove()
        }
        XCTAssertEqual(chflags(oldURL.path, UInt32(UF_IMMUTABLE)), 0)
        let source = try fixture.source(named: "new.txt", data: Data("new".utf8))
        let updated = try await library.replaceFile(for: initial[0].id, at: source)
        guard case .committedWithCleanupIssue(let templates, let issue) = updated else {
            return XCTFail("A committed replacement must carry its cleanup issue without throwing")
        }
        XCTAssertEqual(templates, initial)
        XCTAssertEqual(issue.url, oldURL.deletingLastPathComponent())
        let newContent = try await library.content(for: initial[0].id)
        XCTAssertEqual(newContent.data, Data("new".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(chflags(oldURL.path, 0), 0)
        _ = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
    }

    func testOpeningChecksMissingAndNonregularSavedFiles() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load().templates
        let id = initial[0].id
        let url = try await library.fileURL(for: id)
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await library.fileURL(for: id)
            XCTFail("A missing template file must not be returned for opening")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.readContent, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do {
            _ = try await library.fileURL(for: id)
            XCTFail("A directory must not be returned for opening")
        } catch {
            XCTAssertEqual(error as? FileTemplateLibraryError, .unsupportedFile(url))
        }
    }
}

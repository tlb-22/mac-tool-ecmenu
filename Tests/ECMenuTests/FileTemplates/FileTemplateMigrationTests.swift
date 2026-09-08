import Darwin
import Foundation
import XCTest
@testable import ECMenu

final class FileTemplateMigrationTests: XCTestCase {
    func testLegacyMigrationPreservesIdentitiesNamesOrderAndBytes() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let templates = [
            try FileTemplate(displayName: "Custom", defaultFileName: "report.bin"),
            try FileTemplate(displayName: "Custom", defaultFileName: "LICENSE"),
        ]
        _ = try fixture.saveLegacyIndex(templates)
        let bytes = [Data([0, 255, 128]), Data("license".utf8)]
        let oldURLs = try zip(templates, bytes).map { try fixture.saveLegacyContent($1, for: $0.id) }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)

        let loaded = try await library.load()
        XCTAssertEqual(loaded, templates)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.indexURL)) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        for (index, template) in templates.enumerated() {
            let content = try await library.content(for: template.id)
            XCTAssertEqual(content.template, template)
            XCTAssertEqual(content.data, bytes[index])
            let newURL = try await library.fileURL(for: template.id)
            XCTAssertEqual(newURL.lastPathComponent, template.defaultFileName)
            XCTAssertNotEqual(newURL.deletingLastPathComponent().lastPathComponent, template.id.rawValue.uuidString)
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldURLs[index].path))
        }
        let restarted = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
        XCTAssertEqual(restarted, templates)
    }

    func testEmptyLegacyIndexRemainsEmptyAndCleansUnreferencedContents() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        _ = try fixture.saveLegacyIndex([])
        let orphan = try fixture.saveLegacyContent(Data("orphan".utf8), for: FileTemplateID())
        let loaded = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
        XCTAssertEqual(loaded, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        let current = try JSONDecoder().decode(FileTemplateIndex.self, from: Data(contentsOf: fixture.indexURL))
        XCTAssertTrue(current.templates.isEmpty)
        let restarted = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
        XCTAssertEqual(restarted, [])
    }

    func testMissingLegacyContentDoesNotReplaceIndexOrRemoveValidOldContent() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let templates = [
            try FileTemplate(displayName: "TXT", defaultFileName: "first.txt"),
            try FileTemplate(displayName: "TXT 2", defaultFileName: "second.txt"),
        ]
        let index = try fixture.saveLegacyIndex(templates)
        let bytes = Data("preserve".utf8)
        let firstURL = try fixture.saveLegacyContent(bytes, for: templates[0].id)
        do {
            _ = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
            XCTFail("Migration must not replace missing legacy contents with empty data")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.readContent, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.indexURL), index)
        XCTAssertEqual(try Data(contentsOf: firstURL), bytes)

        _ = try fixture.saveLegacyContent(Data(), for: templates[1].id)
        let recovered = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
        XCTAssertEqual(recovered, templates)
        let directories = try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path)
        XCTAssertEqual(directories.count, templates.count)
    }

    func testFailedMigrationCommitPreservesLegacyIndexAndCanRetry() async throws {
        let fixture = try FileTemplateLibraryFixture()
        let template = try FileTemplate(displayName: "TXT", defaultFileName: "example.txt")
        let legacy = try fixture.saveLegacyIndex([template])
        let bytes = Data("template".utf8)
        let oldURL = try fixture.saveLegacyContent(bytes, for: template.id)
        defer {
            _ = chflags(fixture.indexURL.path, 0)
            fixture.remove()
        }
        XCTAssertEqual(chflags(fixture.indexURL.path, UInt32(UF_IMMUTABLE)), 0)
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        do {
            _ = try await library.load()
            XCTFail("Migration must report an index commit failure")
        } catch let error as FileTemplateLibraryError {
            guard case .fileOperation(.saveIndex, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.indexURL), legacy)
        XCTAssertEqual(try Data(contentsOf: oldURL), bytes)
        XCTAssertEqual(chflags(fixture.indexURL.path, 0), 0)
        let recovered = try await library.load()
        XCTAssertEqual(recovered, [template])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.filesURL.path).count, 1)
    }

    func testInvalidCurrentFileReferencesCannotEscapeLibraryOrAliasAnotherTemplate() async throws {
        let fixture = try FileTemplateLibraryFixture()
        defer { fixture.remove() }
        let library = FileTemplateLibrary(rootURL: fixture.libraryURL)
        let initial = try await library.load()
        let originalURL = try await library.fileURL(for: initial[0].id)
        let savedIndex = try Data(contentsOf: fixture.indexURL)
        let initialJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: savedIndex) as? [String: Any])
        let initialRecords = try XCTUnwrap(initialJSON["templates"] as? [[String: Any]])
        for badName in ["../escape.txt", ".", "", "a/b"] {
            var json = initialJSON
            var record = initialRecords[0]
            var file = try XCTUnwrap(record["file"] as? [String: Any])
            file["fileName"] = badName
            record["file"] = file
            json["templates"] = [record]
            let invalidData = try JSONSerialization.data(withJSONObject: json)
            try invalidData.write(to: fixture.indexURL)
            do {
                _ = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
                XCTFail("Invalid content names must fail decoding")
            } catch let error as FileTemplateLibraryError {
                guard case .invalidIndex = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: fixture.indexURL), invalidData)
            XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        }
        var json = initialJSON
        var duplicateContent = initialRecords[0]
        var otherTemplate = try XCTUnwrap(duplicateContent["template"] as? [String: Any])
        otherTemplate["id"] = UUID().uuidString
        duplicateContent["template"] = otherTemplate
        json["templates"] = [initialRecords[0], duplicateContent]
        let aliasedData = try JSONSerialization.data(withJSONObject: json)
        try aliasedData.write(to: fixture.indexURL)
        do {
            _ = try await FileTemplateLibrary(rootURL: fixture.libraryURL).load()
            XCTFail("Independent templates cannot share a mutable content identity")
        } catch let error as FileTemplateLibraryError {
            guard case .invalidIndex = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.indexURL), aliasedData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
    }
}

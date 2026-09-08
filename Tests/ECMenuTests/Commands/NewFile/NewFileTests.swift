/**
 验证从模板身份读取内容到目标目录独占创建文件的完整执行边界。
 使用隔离模板库和真实文件系统覆盖二进制内容、并发不覆盖及读取和写入失败。
 */

import Darwin
import Foundation
import XCTest
@testable import ECMenu

/// 验证从模板库到目标文件的不覆盖创建边界，不触发 Finder 结果呈现。
final class NewFileTests: XCTestCase {
    func testInitialTXTTemplateCreatesAnEmptyFile() async throws {
        let fixture = try NewFileFixture()
        defer { fixture.remove() }
        let templates = try await fixture.library.load().templates
        let template = try XCTUnwrap(templates.first)
        let handler = fixture.handler
        let result = try await handler.execute(fixture.command(for: template.id)).get()
        XCTAssertEqual(result.fileURL.lastPathComponent, "untitled.txt")
        XCTAssertEqual(try Data(contentsOf: result.fileURL), Data())
    }

    func testSameNamedTemplatesCreateTheirOwnImportedBytesByIdentity() async throws {
        let fixture = try NewFileFixture()
        defer { fixture.remove() }
        let firstBytes = Data([0, 255, 10, 0, 128, 127])
        let secondBytes = Data([255, 0, 13, 10, 192, 128])
        let first = try await fixture.importTemplate(named: "first.bin", data: firstBytes)
        let second = try await fixture.importTemplate(named: "second.bin", data: secondBytes)
        for template in [first, second] {
            _ = try await fixture.library.update(FileTemplate(
                id: template.id,
                displayName: "Binary",
                defaultFileName: "sample.bin"
            ))
        }
        let handler = fixture.handler
        let firstURL = try await handler.execute(fixture.command(for: first.id)).get().fileURL
        let secondURL = try await handler.execute(fixture.command(for: second.id)).get().fileURL
        XCTAssertEqual(firstURL.lastPathComponent, "sample.bin")
        XCTAssertEqual(secondURL.lastPathComponent, "sample_copy.bin")
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)

        _ = try await fixture.library.remove(id: first.id)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)
    }

    func testCreationRespectsDefaultNamesAndContinuesCopyNumbers() async throws {
        let fixture = try NewFileFixture()
        defer { fixture.remove() }
        let bytes = Data("template contents".utf8)
        let existingBytes = Data("existing contents".utf8)
        let template = try await fixture.importTemplate(named: "template.txt", data: bytes)
        let handler = fixture.handler
        let scenarios: [(String, [String], String)] = [
            ("untitled.txt", ["untitled.txt", "untitled_copy.txt"], "untitled_copy2.txt"),
            ("LICENSE", ["LICENSE"], "LICENSE_copy"),
            ("notes_copy.txt", ["notes_copy.txt", "notes_copy2.txt"], "notes_copy3.txt"),
            ("notes_copy2.txt", ["notes_copy2.txt"], "notes_copy3.txt"),
        ]
        for (index, scenario) in scenarios.enumerated() {
            let (defaultName, occupiedNames, expectedName) = scenario
            _ = try await fixture.library.update(FileTemplate(
                id: template.id,
                displayName: template.displayName,
                defaultFileName: defaultName
            ))
            let directoryURL = fixture.destinationURL.appendingPathComponent(String(index))
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
            for name in occupiedNames {
                try existingBytes.write(to: directoryURL.appendingPathComponent(name))
            }
            let command = CreateNewFileCommand(
                directoryPath: try XCTUnwrap(AbsoluteFilePath(url: directoryURL)),
                templateID: template.id
            )
            let result = try await handler.execute(command).get()
            XCTAssertEqual(result.fileURL.lastPathComponent, expectedName)
            XCTAssertEqual(try Data(contentsOf: result.fileURL), bytes)
            for name in occupiedNames {
                XCTAssertEqual(try Data(contentsOf: directoryURL.appendingPathComponent(name)), existingBytes)
            }
        }
    }

    /// 同进程并发命令竞争同一候选序列，所有输出都须完整且互不覆盖。
    func testConcurrentCreationDoesNotOverwriteAndPreservesBinaryContents() async throws {
        let fixture = try NewFileFixture()
        defer { fixture.remove() }
        let bytes = Data((0...255).map(UInt8.init))
        let template = try await fixture.importTemplate(named: "binary.bin", data: bytes)
        let occupiedURL = fixture.destinationURL.appendingPathComponent(template.defaultFileName)
        let occupiedContents = Data("existing contents".utf8)
        try occupiedContents.write(to: occupiedURL)
        let handler = fixture.handler
        let command = try fixture.command(for: template.id)
        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await handler.execute(command).get().fileURL
                }
            }
            var urls: [URL] = []
            for try await url in group {
                urls.append(url)
            }
            return urls
        }
        XCTAssertEqual(Set(urls).count, 8)
        XCTAssertFalse(urls.contains(occupiedURL))
        XCTAssertEqual(try Data(contentsOf: occupiedURL), occupiedContents)
        for url in urls {
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testDeletedTemplateFailsWithoutChoosingAnotherTemplate() async throws {
        let fixture = try NewFileFixture()
        defer { fixture.remove() }
        let templates = try await fixture.library.load().templates
        let template = try XCTUnwrap(templates.first)
        let other = try await fixture.importTemplate(named: "other.txt", data: Data("other".utf8))
        _ = try await fixture.library.update(FileTemplate(
            id: other.id,
            displayName: template.displayName,
            defaultFileName: template.defaultFileName
        ))
        let command = try fixture.command(for: template.id)
        _ = try await fixture.library.remove(id: template.id)
        let handler = fixture.handler
        guard case .failure(.template(let failedID, let error)) = await handler.execute(command) else {
            return XCTFail("A menu item whose template was deleted must be a template failure")
        }
        XCTAssertEqual(failedID, template.id)
        XCTAssertFalse(error.domain.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.destinationURL.path), [])
    }

    func testMissingTemplateCopyFailsBeforeWritingAnyDestinationFile() async throws {
        let fixture = try NewFileFixture()
        defer { fixture.remove() }
        let template = try await fixture.importTemplate(named: "source.txt", data: Data("nonempty".utf8))
        let contentURL = try await fixture.library.fileURL(for: template.id)
        try FileManager.default.removeItem(at: contentURL)
        let handler = fixture.handler
        guard case .failure(.template(let failedID, _)) = try await handler.execute(fixture.command(for: template.id)) else {
            return XCTFail("A missing template copy must not create an empty output")
        }
        XCTAssertEqual(failedID, template.id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.destinationURL.path), [])
    }

    func testMissingDestinationIsClassifiedSeparatelyFromTemplateFailures() async throws {
        let fixture = try NewFileFixture()
        defer { fixture.remove() }
        let templates = try await fixture.library.load().templates
        let template = try XCTUnwrap(templates.first)
        let missingURL = fixture.rootURL.appendingPathComponent("missing")
        let command = CreateNewFileCommand(
            directoryPath: try XCTUnwrap(AbsoluteFilePath(url: missingURL)),
            templateID: template.id
        )
        let handler = fixture.handler
        guard case .failure(.destination(let directoryURL, let error)) = await handler.execute(command) else {
            return XCTFail("An unavailable target directory must be a destination failure")
        }
        XCTAssertEqual(directoryURL, missingURL)
        XCTAssertEqual(FileSystemErrorKind(classifying: error), .unavailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
    }

    /// 目标目录的父目录不能遍历时，存在性查询会丢失 EACCES；创建必须保留权限原因。
    func testUntraversableDestinationReportsPermissionFailure() async throws {
        try XCTSkipIf(geteuid() == 0, "Permission denial requires a non-root test process")
        let fixture = try NewFileFixture()
        defer {
            _ = chmod(fixture.destinationURL.path, 0o755)
            fixture.remove()
        }
        let templates = try await fixture.library.load().templates
        let template = try XCTUnwrap(templates.first)
        let directoryURL = fixture.destinationURL.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        let command = CreateNewFileCommand(
            directoryPath: try XCTUnwrap(AbsoluteFilePath(url: directoryURL)),
            templateID: template.id
        )
        guard chmod(fixture.destinationURL.path, 0) == 0 else {
            return XCTFail("Could not make the fixture directory untraversable: \(errno)")
        }
        let handler = fixture.handler
        guard case .failure(let failure) = await handler.execute(command),
              case .destination(let failedURL, let error) = failure else {
            return XCTFail("An untraversable destination must fail at the destination boundary")
        }
        XCTAssertEqual(failedURL, directoryURL)
        XCTAssertEqual(FileSystemErrorKind(classifying: error), .permissionDenied)
        XCTAssertNotNil(CreateNewFileAlertContent.make(for: failure))
        XCTAssertEqual(chmod(fixture.destinationURL.path, 0o755), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path), [])
    }

    func testRegularFileCannotBeUsedAsDestinationDirectory() async throws {
        let fixture = try NewFileFixture()
        defer { fixture.remove() }
        let templates = try await fixture.library.load().templates
        let template = try XCTUnwrap(templates.first)
        let fileURL = fixture.rootURL.appendingPathComponent("occupied.txt")
        let original = Data("existing contents".utf8)
        try original.write(to: fileURL)
        let command = CreateNewFileCommand(
            directoryPath: try XCTUnwrap(AbsoluteFilePath(url: fileURL)),
            templateID: template.id
        )
        let handler = fixture.handler
        guard case .failure(.destination(let failedURL, _)) = await handler.execute(command) else {
            return XCTFail("A regular-file target must be a destination failure")
        }
        XCTAssertEqual(failedURL, fileURL)
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.destinationURL.path), [])
    }
}

nonisolated private struct NewFileFixture {
    let rootURL: URL
    let library: FileTemplateLibrary

    init() throws {
        let rootURL = try ProjectTestDirectory.makeUniqueDirectory()
        self.rootURL = rootURL
        library = FileTemplateLibrary(rootURL: rootURL.appendingPathComponent("NewFileTemplates"))
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: false)
    }

    var handler: CreateNewFileHandler {
        CreateNewFileHandler(
            readTemplate: { [library] in try await library.content(for: $0) },
            writer: .system,
            present: { _, _ in }
        )
    }

    var libraryURL: URL { rootURL.appendingPathComponent("NewFileTemplates") }
    var destinationURL: URL { rootURL.appendingPathComponent("destination", isDirectory: true) }

    func importTemplate(named name: String, data: Data) async throws -> FileTemplate {
        let sourceURL = rootURL.appendingPathComponent(name)
        try data.write(to: sourceURL)
        let templates = try await library.importFile(at: sourceURL).templates
        return try XCTUnwrap(templates.last)
    }

    func command(for id: FileTemplateID) throws -> CreateNewFileCommand {
        CreateNewFileCommand(
            directoryPath: try XCTUnwrap(AbsoluteFilePath(url: destinationURL)),
            templateID: id
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

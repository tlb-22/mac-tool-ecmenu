/**
 为模板测试提供项目内独立目录、索引和内容文件的构造与清理工具。
 统一定位当前索引和内容副本，使持久化测试能够控制文件状态与失败条件。
 */

import Foundation
import XCTest
@testable import ECMenu

nonisolated struct FileTemplateLibraryFixture {
    let rootURL: URL

    init() throws {
        rootURL = try ProjectTestDirectory.makeUniqueDirectory()
    }

    var libraryURL: URL { rootURL.appendingPathComponent("FileTemplates", isDirectory: true) }
    var filesURL: URL { libraryURL.appendingPathComponent("Files", isDirectory: true) }
    var indexURL: URL { libraryURL.appendingPathComponent("index.json") }

    func contentURL(for id: FileTemplateID) throws -> URL {
        let index = try JSONDecoder().decode(FileTemplateIndex.self, from: Data(contentsOf: indexURL))
        let file = try XCTUnwrap(index.templates.first { $0.template.id == id }).file
        return filesURL.appendingPathComponent(file.id.uuidString, isDirectory: true)
            .appendingPathComponent(file.fileName)
    }

    func source(named name: String, data: Data) throws -> URL {
        let url = rootURL.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

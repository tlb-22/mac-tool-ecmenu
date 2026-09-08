import Darwin
import Foundation
import OSLog

/// 主应用唯一拥有的模板库；文件 I/O 在 actor 中串行执行。
actor FileTemplateLibrary {
    nonisolated static var defaultRootURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(ApplicationIPC.applicationSigningIdentifier, isDirectory: true)
            .appendingPathComponent("FileTemplates", isDirectory: true)
    }

    private enum Location {
        case applicationSupport
        case directory(URL)
    }

    private let location: Location
    private var templates: [FileTemplate]?
    private let fileManager = FileManager.default
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "FileTemplates"
    )

    init() {
        location = .applicationSupport
    }

    init(rootURL: URL) {
        location = .directory(rootURL)
    }

    /// 恢复索引或执行唯一一次初始化；空索引保留用户已删除全部模板的状态。
    func load() throws -> [FileTemplate] {
        if let templates {
            return templates
        }

        let data: Data
        do {
            data = try Data(contentsOf: indexURL)
        } catch {
            if isMissingFile(error), !fileManager.fileExists(atPath: rootURL.path) {
                return try initialize()
            }
            throw failure(.readIndex, at: indexURL, error: error)
        }

        let index: FileTemplateIndex
        do {
            index = try JSONDecoder().decode(FileTemplateIndex.self, from: data)
        } catch let error as FileTemplateLibraryError {
            throw error
        } catch {
            throw FileTemplateLibraryError.invalidIndex(SystemErrorSnapshot(capturing: error))
        }

        templates = index.templates
        cleanUnreferencedFiles(referencedBy: index.templates)
        return index.templates
    }

    /// 完整保存普通源文件的内容后，再把新模板追加到索引。
    func importFile(at sourceURL: URL) throws -> [FileTemplate] {
        var current = try currentTemplates()
        let data = try readContent(at: sourceURL)
        let template = try Self.importedTemplate(from: sourceURL, existing: current)
        try prepareFilesDirectory()
        try saveContent(data, for: template.id)
        current.append(template)
        try commit(current)
        return current
    }

    /// 名称修改只写索引，保留稳定身份、内容和列表顺序。
    func update(_ template: FileTemplate) throws -> [FileTemplate] {
        var current = try currentTemplates()
        guard let position = current.firstIndex(where: { $0.id == template.id }) else {
            throw FileTemplateLibraryError.templateNotFound(template.id)
        }
        current[position] = template
        try commit(current)
        return current
    }

    /// 先提交元数据删除，再清理副本；清理失败仍报告错误，已提交状态可重新加载。
    func remove(id: FileTemplateID) throws -> [FileTemplate] {
        var current = try currentTemplates()
        guard let position = current.firstIndex(where: { $0.id == id }) else {
            throw FileTemplateLibraryError.templateNotFound(id)
        }
        current.remove(at: position)
        try commit(current)
        try removeContent(at: contentURL(for: id))
        return current
    }

    /// 在同一串行事务中按身份取得元数据与独立字节快照。
    func content(for id: FileTemplateID) throws -> FileTemplateContent {
        guard let template = try currentTemplates().first(where: { $0.id == id }) else {
            throw FileTemplateLibraryError.templateNotFound(id)
        }
        return FileTemplateContent(
            template: template,
            data: try readContent(at: contentURL(for: id))
        )
    }

    /// 生产身份仅在实际访问模板库时解析；注册命令和预览构造不依赖应用身份。
    private var rootURL: URL {
        switch location {
        case .applicationSupport: Self.defaultRootURL
        case .directory(let url): url
        }
    }

    private var indexURL: URL {
        rootURL.appendingPathComponent("index.json", isDirectory: false)
    }

    private var filesURL: URL {
        rootURL.appendingPathComponent("Files", isDirectory: true)
    }

    private func contentURL(for id: FileTemplateID) -> URL {
        filesURL.appendingPathComponent(id.rawValue.uuidString, isDirectory: false)
    }

    private func currentTemplates() throws -> [FileTemplate] {
        if let templates {
            return templates
        }
        return try load()
    }

    private func initialize() throws -> [FileTemplate] {
        let template = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        try prepareFilesDirectory()
        try saveContent(Data(), for: template.id)
        try commit([template])
        cleanUnreferencedFiles(referencedBy: [template])
        return [template]
    }

    private func prepareFilesDirectory() throws {
        do {
            try fileManager.createDirectory(at: filesURL, withIntermediateDirectories: true)
        } catch {
            throw failure(.prepareDirectory, at: filesURL, error: error)
        }
    }

    private func saveContent(_ data: Data, for id: FileTemplateID) throws {
        let url = contentURL(for: id)
        do {
            try data.write(to: url, options: .withoutOverwriting)
        } catch {
            throw failure(.saveContent, at: url, error: error)
        }
    }

    private func commit(_ updated: [FileTemplate]) throws {
        // 编码只有已验证值的固定结构，不含可能由用户输入触发的编码失败。
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try! encoder.encode(FileTemplateIndex(templates: updated))
        do {
            try data.write(to: indexURL, options: .atomic)
        } catch {
            throw failure(.saveIndex, at: indexURL, error: error)
        }
        templates = updated
    }

    /// O_NOFOLLOW 与 fstat 约束实际打开的对象，避免符号链接或特殊文件被读取。
    private func readContent(at url: URL) throws -> Data {
        guard url.isFileURL else {
            throw FileTemplateLibraryError.unsupportedFile(url)
        }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw FileTemplateLibraryError.unsupportedFile(url)
            }
            throw failure(.readContent, at: url, error: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else {
            throw failure(.readContent, at: url, error: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
        guard attributes.st_mode & S_IFMT == S_IFREG else {
            throw FileTemplateLibraryError.unsupportedFile(url)
        }
        do {
            return try handle.readToEnd() ?? Data()
        } catch {
            throw failure(.readContent, at: url, error: error)
        }
    }

    private func removeContent(at url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            guard !isMissingFile(error) else { return }
            throw failure(.removeContent, at: url, error: error)
        }
    }

    /// 未引用副本不参与任何模板解析；维护失败只记录诊断，不阻塞有效索引。
    private func cleanUnreferencedFiles(referencedBy templates: [FileTemplate]) {
        let referencedNames = Set(templates.map { $0.id.rawValue.uuidString })
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: filesURL,
                includingPropertiesForKeys: nil
            )
            for url in urls where !referencedNames.contains(url.lastPathComponent) {
                try removeContent(at: url)
            }
        } catch {
            Self.logger.error("Could not clean unused template files: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func failure(
        _ operation: FileTemplateFileOperation,
        at url: URL,
        error: Error
    ) -> FileTemplateLibraryError {
        .fileOperation(operation, url: url, cause: SystemErrorSnapshot(capturing: error))
    }

    private func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain && (
            error.code == CocoaError.fileReadNoSuchFile.rawValue ||
            error.code == CocoaError.fileNoSuchFile.rawValue
        )) || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
    }

    /// 自动避重只发生在导入时，不限制用户随后手动保存的重复名称。
    private static func importedTemplate(from sourceURL: URL, existing: [FileTemplate]) throws -> FileTemplate {
        let pathExtension = sourceURL.pathExtension
        let baseName = pathExtension.isEmpty ? sourceURL.lastPathComponent : pathExtension.uppercased()
        let usedNames = Set(existing.map(\.displayName))
        var displayName = baseName
        var suffix = 2
        while usedNames.contains(displayName) {
            displayName = "\(baseName) \(suffix)"
            suffix += 1
        }
        return try FileTemplate(
            displayName: displayName,
            defaultFileName: pathExtension.isEmpty ? "untitled" : "untitled.\(pathExtension)"
        )
    }
}

/// 单次创建命令消费的不可变内容，不暴露内部库路径。
nonisolated struct FileTemplateContent: Equatable, Sendable {
    let template: FileTemplate
    let data: Data
}

/// 索引专用版本信封；同一个身份不能在清单中占据多个位置。
nonisolated private struct FileTemplateIndex: Codable {
    let templates: [FileTemplate]

    init(templates: [FileTemplate]) {
        self.templates = templates
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, templates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw FileTemplateLibraryError.unsupportedSchema(schemaVersion)
        }
        templates = try container.decode([FileTemplate].self, forKey: .templates)
        guard Set(templates.map(\.id)).count == templates.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .templates,
                in: container,
                debugDescription: "A file template ID occurs more than once"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(templates, forKey: .templates)
    }
}

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
    private var records: [FileTemplateRecord]?
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
        if let records {
            return records.map(\.template)
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
            if let migrated = try FileTemplateIndexMigration.migrateIfNeeded(data, copyContent: { template in
                let oldURL = filesURL.appendingPathComponent(template.id.rawValue.uuidString)
                return try saveContent(readContent(at: oldURL), named: template.defaultFileName)
            }) {
                try commit(migrated.templates)
                index = migrated
            } else {
                index = try JSONDecoder().decode(FileTemplateIndex.self, from: data)
            }
        } catch let error as FileTemplateLibraryError {
            throw error
        } catch {
            throw FileTemplateLibraryError.invalidIndex(SystemErrorSnapshot(capturing: error))
        }

        records = index.templates
        cleanUnreferencedFiles(referencedBy: index.templates)
        return index.templates.map(\.template)
    }

    /// 完整保存普通源文件的内容后，再把新模板追加到索引。
    func importFile(at sourceURL: URL) throws -> [FileTemplate] {
        var current = try currentRecords()
        let data = try readContent(at: sourceURL)
        let template = try Self.importedTemplate(from: sourceURL, existing: current.map(\.template))
        let file = try saveContent(data, named: sourceURL.lastPathComponent)
        current.append(FileTemplateRecord(template: template, file: file))
        do {
            try commit(current)
        } catch {
            cleanContent(at: directoryURL(for: file))
            throw error
        }
        return current.map(\.template)
    }

    /// 名称修改只提交元数据，保留稳定身份、内容和列表顺序。
    func update(_ template: FileTemplate) throws -> [FileTemplate] {
        var current = try currentRecords()
        guard let position = current.firstIndex(where: { $0.template.id == template.id }) else {
            throw FileTemplateLibraryError.templateNotFound(template.id)
        }
        current[position] = FileTemplateRecord(template: template, file: current[position].file)
        try commit(current)
        return current.map(\.template)
    }

    /// 完整复制选定文件后原子发布新引用，保留模板身份、名称和列表顺序。
    func replaceFile(for id: FileTemplateID, at sourceURL: URL) throws -> [FileTemplate] {
        var current = try currentRecords()
        guard let position = current.firstIndex(where: { $0.template.id == id }) else {
            throw FileTemplateLibraryError.templateNotFound(id)
        }
        let original = current[position]
        let file = try saveContent(readContent(at: sourceURL), named: sourceURL.lastPathComponent)
        current[position] = FileTemplateRecord(template: original.template, file: file)
        do {
            try commit(current)
        } catch {
            cleanContent(at: directoryURL(for: file))
            throw error
        }
        // 提交已经成功；旧副本维护失败不可把成功更换变为可重试的提交失败。
        cleanContent(at: directoryURL(for: original.file))
        return current.map(\.template)
    }

    /// 先提交元数据删除，再清理副本；清理失败仍报告错误，已提交状态可重新加载。
    func remove(id: FileTemplateID) throws -> [FileTemplate] {
        var current = try currentRecords()
        guard let position = current.firstIndex(where: { $0.template.id == id }) else {
            throw FileTemplateLibraryError.templateNotFound(id)
        }
        let removed = current.remove(at: position)
        try commit(current)
        try removeContent(at: directoryURL(for: removed.file))
        return current.map(\.template)
    }

    /// 每次从实际文件取得独立字节快照，使默认应用保存的编辑用于下一次创建。
    func content(for id: FileTemplateID) throws -> FileTemplateContent {
        let record = try record(for: id)
        return FileTemplateContent(
            template: record.template,
            data: try readContent(at: contentURL(for: record.file))
        )
    }

    /// 提供已保存的内部副本；只检查普通文件，不为系统打开操作读取全部内容。
    func fileURL(for id: FileTemplateID) throws -> URL {
        let record = try record(for: id)
        let url = contentURL(for: record.file)
        try validateRegularFile(at: url)
        return url
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

    private func directoryURL(for file: FileTemplateFileReference) -> URL {
        filesURL.appendingPathComponent(file.id.uuidString, isDirectory: true)
    }

    private func contentURL(for file: FileTemplateFileReference) -> URL {
        directoryURL(for: file).appendingPathComponent(file.fileName, isDirectory: false)
    }

    private func currentRecords() throws -> [FileTemplateRecord] {
        if let records { return records }
        _ = try load()
        return records!
    }

    private func record(for id: FileTemplateID) throws -> FileTemplateRecord {
        guard let record = try currentRecords().first(where: { $0.template.id == id }) else {
            throw FileTemplateLibraryError.templateNotFound(id)
        }
        return record
    }

    private func initialize() throws -> [FileTemplate] {
        let template = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        let file = try saveContent(Data(), named: "untitled.txt")
        let initial = [FileTemplateRecord(template: template, file: file)]
        try commit(initial)
        cleanUnreferencedFiles(referencedBy: initial)
        return [template]
    }

    private func saveContent(_ data: Data, named fileName: String) throws -> FileTemplateFileReference {
        let file = try FileTemplateFileReference(fileName: fileName)
        let directory = directoryURL(for: file)
        do {
            try fileManager.createDirectory(at: filesURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        } catch {
            throw failure(.prepareDirectory, at: directory, error: error)
        }
        let url = contentURL(for: file)
        do {
            try data.write(to: url, options: .withoutOverwriting)
        } catch {
            cleanContent(at: directory)
            throw failure(.saveContent, at: url, error: error)
        }
        return file
    }

    private func commit(_ updated: [FileTemplateRecord]) throws {
        // 编码只有已验证值的固定结构，不含可能由用户输入触发的编码失败。
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try! encoder.encode(FileTemplateIndex(templates: updated))
        do {
            try data.write(to: indexURL, options: .atomic)
        } catch {
            throw failure(.saveIndex, at: indexURL, error: error)
        }
        records = updated
    }

    private func readContent(at url: URL) throws -> Data {
        try withRegularFile(at: url) { handle in
            do {
                return try handle.readToEnd() ?? Data()
            } catch {
                throw failure(.readContent, at: url, error: error)
            }
        }
    }

    private func validateRegularFile(at url: URL) throws {
        try withRegularFile(at: url) { _ in () }
    }

    /// O_NOFOLLOW 与 fstat 约束实际打开的对象，避免符号链接或特殊文件被读取。
    private func withRegularFile<T>(at url: URL, body: (FileHandle) throws -> T) throws -> T {
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
        return try body(handle)
    }

    private func removeContent(at url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            guard !isMissingFile(error) else { return }
            throw failure(.removeContent, at: url, error: error)
        }
    }

    private func cleanContent(at url: URL) {
        do {
            try removeContent(at: url)
        } catch {
            Self.logger.error("Could not clean unused template files: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 只在恢复索引时清理孤儿，保留有效索引引用的内容目录。
    private func cleanUnreferencedFiles(referencedBy records: [FileTemplateRecord]) {
        let referencedNames = Set(records.map { $0.file.id.uuidString })
        do {
            let urls = try fileManager.contentsOfDirectory(at: filesURL, includingPropertiesForKeys: nil)
            for url in urls where !referencedNames.contains(url.lastPathComponent) {
                cleanContent(at: url)
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

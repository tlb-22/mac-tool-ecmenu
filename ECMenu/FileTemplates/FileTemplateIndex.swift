import Foundation

/// 名称属于模板元数据；文件引用在更换内容时独立更新。
nonisolated struct FileTemplateRecord: Codable, Equatable, Sendable {
    let template: FileTemplate
    let file: FileTemplateFileReference
}

nonisolated struct FileTemplateFileReference: Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String

    init(fileName: String) throws {
        try Self.validate(fileName)
        id = UUID()
        self.fileName = fileName
    }

    private enum CodingKeys: String, CodingKey {
        case id, fileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        try Self.validate(fileName)
    }

    private static func validate(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileTemplateValidationError.invalidDefaultFileName
        }
    }
}

/// 当前索引只接受当前格式；历史格式由独立迁移转换后提交。
nonisolated struct FileTemplateIndex: Codable {
    static let schemaVersion = 2
    let templates: [FileTemplateRecord]

    init(templates: [FileTemplateRecord]) {
        self.templates = templates
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, templates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.schemaVersion else {
            throw FileTemplateLibraryError.unsupportedSchema(schemaVersion)
        }
        templates = try container.decode([FileTemplateRecord].self, forKey: .templates)
        guard Set(templates.map(\.template.id)).count == templates.count,
              Set(templates.map(\.file.id)).count == templates.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .templates,
                in: container,
                debugDescription: "Template and content identities must each be unique"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(templates, forKey: .templates)
    }
}

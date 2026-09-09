/**
 定义模板索引的当前持久化结构和编码版本。
 以有序记录保存完整模板清单，并在读取时校验版本与身份唯一性。
 */

import Foundation

/// 索引只接受当前格式，其他版本明确报告不受支持。
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

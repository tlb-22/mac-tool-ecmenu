import Foundation

/// schema 1 未保存源文件名；迁移用默认文件名恢复可由系统打开的副本名称。
/// 所有内容复制完成后由库原子发布新索引，原索引和旧副本在此前始终有效。
nonisolated enum FileTemplateIndexMigration {
    static func migrateIfNeeded(
        _ data: Data,
        copyContent: (FileTemplate) throws -> FileTemplateFileReference
    ) throws -> FileTemplateIndex? {
        let decoder = JSONDecoder()
        let version = try decoder.decode(Version.self, from: data).schemaVersion
        guard version == 1 else { return nil }
        let oldIndex = try decoder.decode(LegacyIndex.self, from: data)
        return try FileTemplateIndex(templates: oldIndex.templates.map {
            FileTemplateRecord(template: $0, file: try copyContent($0))
        })
    }

    nonisolated private struct Version: Decodable {
        let schemaVersion: Int
    }

    nonisolated private struct LegacyIndex: Decodable {
        let templates: [FileTemplate]

        private enum CodingKeys: String, CodingKey {
            case templates
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            templates = try container.decode([FileTemplate].self, forKey: .templates)
            guard Set(templates.map(\.id)).count == templates.count else {
                throw DecodingError.dataCorruptedError(
                    forKey: .templates,
                    in: container,
                    debugDescription: "A file template ID occurs more than once"
                )
            }
        }
    }
}

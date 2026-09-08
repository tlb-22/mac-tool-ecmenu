/**
 定义模板元数据与库内副本引用组成的持久化记录。
 用受约束的相对文件引用表达存储位置，保持模板身份与内容副本身份独立。
 */

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

/**
 限定主应用发布给 Finder 的模板菜单信息：稳定身份、显示名称和文件名后缀。
 传输解码拒绝空白名称；后缀供系统图标查询，内容、完整文件名与存储位置由主应用拥有。
 */

import Foundation

/// 主应用向 Finder 发布的模板菜单信息，不暴露内部文件路径。
nonisolated struct FileTemplateMenuItem: Codable, Equatable, Sendable {
    let id: FileTemplateID
    let displayName: String
    let filenameExtension: String

    init(id: FileTemplateID, displayName: String, filenameExtension: String) {
        precondition(!displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.id = id
        self.displayName = displayName
        self.filenameExtension = filenameExtension
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case filenameExtension
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let displayName = try container.decode(String.self, forKey: .displayName)
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .displayName,
                in: container,
                debugDescription: "A template menu display name cannot be empty"
            )
        }
        id = try container.decode(FileTemplateID.self, forKey: .id)
        self.displayName = displayName
        filenameExtension = try container.decode(String.self, forKey: .filenameExtension)
    }
}

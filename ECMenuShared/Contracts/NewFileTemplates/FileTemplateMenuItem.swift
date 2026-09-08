/**
 限定主应用发布给 Finder 的模板菜单信息，只交付稳定身份与经过验证的显示名称。
 传输解码拒绝空白名称，模板内容、默认文件名与内部存储位置由主应用独立拥有。
 */

import Foundation

/// 主应用向 Finder 发布的模板菜单信息，不暴露内部文件路径。
nonisolated struct FileTemplateMenuItem: Codable, Equatable, Sendable {
    let id: FileTemplateID
    let displayName: String

    init(id: FileTemplateID, displayName: String) {
        precondition(!displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.id = id
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
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
    }
}

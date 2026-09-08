/**
 定义模板稳定身份、显示名称和默认文件名组成的有效管理模型。
 在创建及解码时验证名称约束，并提供名称编辑可直接呈现的输入错误。
 */

import Foundation

/// 主应用拥有的已验证模板元数据，内容副本由持久化索引关联。
nonisolated struct FileTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: FileTemplateID
    let displayName: String
    let defaultFileName: String

    init(
        id: FileTemplateID = FileTemplateID(),
        displayName: String,
        defaultFileName: String
    ) throws {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileTemplateValidationError.emptyDisplayName
        }
        guard
            !defaultFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            defaultFileName != ".",
            defaultFileName != "..",
            !defaultFileName.contains("/"),
            !defaultFileName.contains("\0")
        else {
            throw FileTemplateValidationError.invalidDefaultFileName
        }

        self.id = id
        self.displayName = displayName
        self.defaultFileName = defaultFileName
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, defaultFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(FileTemplateID.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            defaultFileName: container.decode(String.self, forKey: .defaultFileName)
        )
    }
}

/// 可以在名称编辑边界直接呈现的输入错误；重名是有效输入。
nonisolated enum FileTemplateValidationError: Error, Equatable, LocalizedError {
    case emptyDisplayName
    case invalidDefaultFileName

    var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            String(localized: "Enter a display name.")
        case .invalidDefaultFileName:
            String(localized: "Enter a single file name, without a folder path.")
        }
    }
}

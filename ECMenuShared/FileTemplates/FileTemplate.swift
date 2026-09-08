import Foundation

/// 模板在持久化与跨进程命令中的稳定身份，不依赖可编辑名称。
nonisolated struct FileTemplateID: Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 一个已验证、与模板内容通过 ID 关联的不可变菜单条目。
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

/**
 把菜单开关、命令顺序与有序模板描述组合为可跨进程整体应用的快照，区分有效空库和模板不可用。
 编解码验证独立 schema 与模板身份唯一性，接收端可以据此拒绝整份无效响应。
 */

import Foundation

/// 模板读取失败独立于菜单开关；有效空库与暂不可用保留不同语义。
nonisolated enum FileTemplateMenuState: Codable, Equatable, Sendable {
    case available([FileTemplateMenuItem])
    case unavailable

    var items: [FileTemplateMenuItem] {
        switch self {
        case .available(let items): items
        case .unavailable: []
        }
    }
}

/// 主应用发布的完整菜单事实；模板库仍由主应用独立持有。
nonisolated struct CommandMenuSettingsSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let standard = CommandMenuSettingsSnapshot(
        configuration: .standard,
        fileTemplateState: .unavailable
    )

    let configuration: CommandMenuSettings
    let fileTemplateState: FileTemplateMenuState
    var newFileTemplates: [FileTemplateMenuItem] { fileTemplateState.items }

    init(configuration: CommandMenuSettings, newFileTemplates: [FileTemplateMenuItem]) {
        self.init(configuration: configuration, fileTemplateState: .available(newFileTemplates))
    }

    init(configuration: CommandMenuSettings, fileTemplateState: FileTemplateMenuState) {
        precondition(Set(fileTemplateState.items.map(\.id)).count == fileTemplateState.items.count)
        self.configuration = configuration
        self.fileTemplateState = fileTemplateState
    }

    var isEnabled: Bool { configuration.isEnabled }
    var hiddenFeatureIDs: Set<String> { configuration.hiddenFeatureIDs }

    func isVisible(_ feature: ContextCommandFeatureID) -> Bool {
        configuration.isVisible(feature)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case configuration
        case newFileTemplates = "fileTemplates"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: "Unsupported menu snapshot schema"
            )
        }
        configuration = try container.decode(CommandMenuSettings.self, forKey: .configuration)
        fileTemplateState = try container.decode(FileTemplateMenuState.self, forKey: .newFileTemplates)
        guard Set(newFileTemplates.map(\.id)).count == newFileTemplates.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .newFileTemplates, in: container,
                debugDescription: "A menu snapshot contains duplicate template identities"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(fileTemplateState, forKey: .newFileTemplates)
    }
}

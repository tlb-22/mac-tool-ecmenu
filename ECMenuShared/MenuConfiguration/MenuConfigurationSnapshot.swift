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
nonisolated struct MenuConfigurationSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let standard = MenuConfigurationSnapshot(
        configuration: .standard,
        fileTemplateState: .unavailable
    )

    let configuration: MenuConfiguration
    let fileTemplateState: FileTemplateMenuState
    var fileTemplates: [FileTemplateMenuItem] { fileTemplateState.items }

    init(configuration: MenuConfiguration, fileTemplates: [FileTemplateMenuItem]) {
        self.init(configuration: configuration, fileTemplateState: .available(fileTemplates))
    }

    init(configuration: MenuConfiguration, fileTemplateState: FileTemplateMenuState) {
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
        case fileTemplates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: "Unsupported menu snapshot schema"
            )
        }
        configuration = try container.decode(MenuConfiguration.self, forKey: .configuration)
        fileTemplateState = try container.decode(FileTemplateMenuState.self, forKey: .fileTemplates)
        guard Set(fileTemplates.map(\.id)).count == fileTemplates.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .fileTemplates, in: container,
                debugDescription: "A menu snapshot contains duplicate template identities"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(fileTemplateState, forKey: .fileTemplates)
    }
}

/// Extension 的派生缓存格式独立于主应用的菜单开关偏好格式。
nonisolated enum MenuConfigurationSnapshotCache {
    static let key = "menu-configuration-snapshot-v1"

    static func encode(_ snapshot: MenuConfigurationSnapshot) -> Data {
        try! JSONEncoder().encode(snapshot)
    }

    static func decode(_ data: Data) throws -> MenuConfigurationSnapshot {
        try JSONDecoder().decode(MenuConfigurationSnapshot.self, from: data)
    }
}

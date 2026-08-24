import Foundation

/// 跨主应用和 Finder Extension 共享的不可变菜单配置值。
nonisolated struct MenuConfiguration: Codable, Equatable, Sendable {
    /// 当前持久化和传输格式版本；领域状态本身不保存该值。
    static let currentSchemaVersion = MenuConfigurationEnvelope.currentSchemaVersion

    /// 所有功能使用产品默认可见性时的配置。
    static let standard = MenuConfiguration()

    /// 产品是否向 Finder 贡献任何右键菜单项。
    private(set) var isEnabled: Bool

    /// 偏离默认可见状态的功能稳定标识集合。
    private(set) var hiddenFeatureIDs: Set<String>

    /// 创建产品启用状态和隐藏功能集合组成的有效领域配置。
    init(
        isEnabled: Bool = true,
        hiddenFeatureIDs: Set<String> = []
    ) {
        self.isEnabled = isEnabled
        self.hiddenFeatureIDs = hiddenFeatureIDs
    }

    /// 设置产品是否向 Finder 贡献右键菜单，不改变各功能的独立可见性。
    /// - Parameter isEnabled: 新的产品总开关状态。
    mutating func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// 计算功能自身的显示配置，不合并产品总开关。
    /// - Parameter feature: 固定右键功能标识。
    /// - Returns: 功能标识不在稀疏隐藏集合中时为 `true`。
    func isVisible(_ feature: ContextCommandFeatureID) -> Bool {
        !hiddenFeatureIDs.contains(feature.rawValue)
    }

    /// 设置功能可见性，只保存偏离默认可见状态的功能标识。
    /// - Parameters:
    ///   - isVisible: 功能的新显示状态。
    ///   - feature: 需要修改的固定功能。
    mutating func setVisible(
        _ isVisible: Bool,
        for feature: ContextCommandFeatureID
    ) {
        if isVisible {
            hiddenFeatureIDs.remove(feature.rawValue)
        } else {
            hiddenFeatureIDs.insert(feature.rawValue)
        }
    }

    /// 通过版本化信封恢复领域状态。
    init(from decoder: Decoder) throws {
        self = try MenuConfigurationEnvelope(from: decoder).configuration
    }

    /// 把领域状态包装为当前版本信封。
    func encode(to encoder: Encoder) throws {
        try MenuConfigurationEnvelope(configuration: self).encode(to: encoder)
    }
}

/// 持久化与传输专用的版本信封；解码后只向业务层交付有效配置。
nonisolated private struct MenuConfigurationEnvelope: Codable, Sendable {
    /// 当前持久化和传输格式版本。
    static let currentSchemaVersion = 3

    /// 从当前或旧格式恢复出的有效领域状态。
    let configuration: MenuConfiguration

    /// 配置持久化和传输使用的稳定字段名。
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case hiddenFeatureIDs
        case visibilityOverrides
    }

    /// 使用当前领域状态创建待编码信封。
    init(configuration: MenuConfiguration) {
        self.configuration = configuration
    }

    /// 解码当前格式，并把旧格式中的关闭覆盖迁移为领域状态。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1

        switch decodedVersion {
        case Self.currentSchemaVersion:
            configuration = MenuConfiguration(
                isEnabled: try container.decode(
                    Bool.self,
                    forKey: .isEnabled
                ),
                hiddenFeatureIDs: Set(
                    try container.decodeIfPresent(
                        [String].self,
                        forKey: .hiddenFeatureIDs
                    ) ?? []
                )
            )

        case 2:
            configuration = MenuConfiguration(
                hiddenFeatureIDs: Set(
                    try container.decodeIfPresent(
                        [String].self,
                        forKey: .hiddenFeatureIDs
                    ) ?? []
                )
            )

        case 1:
            let overrides = try container.decodeIfPresent(
                [String: Bool].self,
                forKey: .visibilityOverrides
            ) ?? [:]
            configuration = MenuConfiguration(
                hiddenFeatureIDs: Set(
                    overrides.compactMap { identifier, isVisible in
                        isVisible ? nil : identifier
                    }
                )
            )

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported menu configuration schema"
            )
        }
    }

    /// 始终编码为当前格式，并按稳定顺序写入隐藏功能标识。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(configuration.isEnabled, forKey: .isEnabled)
        try container.encode(
            configuration.hiddenFeatureIDs.sorted(),
            forKey: .hiddenFeatureIDs
        )
    }
}

/// 定义菜单配置的纯编解码格式和无数据更新信号。
nonisolated enum MenuConfigurationChannel {
    /// 主应用提示配置可能变化的无数据分布式通知。
    ///
    /// 该信号不携带任何权威数据；Extension 收到后必须通过双向身份验证的
    /// 定向 socket 重新拉取配置。
    static let didChangeNotification = Notification.Name(
        "\(ApplicationIPC.applicationSigningIdentifier).menu-configuration.did-change"
    )

    /// 两个进程各自缓存配置快照时使用的稳定偏好键；格式版本保存在值内部。
    static let persistedConfigurationKey = "menu-configuration-v1"

    /// 把配置编码为持久化或传输使用的数据。
    /// - Parameter configuration: 需要编码的配置快照。
    /// - Returns: 编码成功的数据；理论上的编码失败返回 `nil`。
    static func encodedData(for configuration: MenuConfiguration) -> Data? {
        try? JSONEncoder().encode(configuration)
    }

    /// 从持久化数据解码并验证配置版本。
    /// - Parameter data: 编码后的配置数据。
    /// - Returns: 当前格式的配置；数据无效或版本不受支持时返回 `nil`。
    static func decodedConfiguration(from data: Data) -> MenuConfiguration? {
        try? JSONDecoder().decode(MenuConfiguration.self, from: data)
    }

    /// 只广播一次重新拉取提示，不发布配置正文。
    static func signalConfigurationChange() {
        DistributedNotificationCenter.default().postNotificationName(
            didChangeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

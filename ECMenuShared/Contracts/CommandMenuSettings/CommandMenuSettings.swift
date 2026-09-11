/**
 定义两个产品共同理解的菜单配置及其版本化 JSON 信封，保存总开关、隐藏功能集合和命令顺序。
 业务修改使用有效值，解码严格验证当前格式；实际偏好读写由各进程的存储边界负责。
 */

import Foundation

/// 跨主应用和 Finder Extension 共享的不可变菜单配置值。
nonisolated struct CommandMenuSettings: Codable, Equatable, Sendable {
    /// 当前持久化和传输格式版本；领域状态本身不保存该值。
    static let currentSchemaVersion = CommandMenuSettingsEnvelope.currentSchemaVersion

    /// 产品默认开关、可见性与命令顺序。
    static let standard = CommandMenuSettings()

    /// 当前产品的完整默认顺序；显示过滤不会改变这份功能集合。
    static let defaultFeatureIDs: [ContextCommandFeatureID] = [
        CreateNewFileCommand.descriptor.id,
        CopyPathCommand.descriptor.id,
        HideItemsCommand.descriptor.id,
        ShowItemsCommand.descriptor.id,
        CompressImagesCommand.descriptor.id,
        OpenInVSCodeCommand.descriptor.id,
        OpenInITerm2Command.descriptor.id,
    ]

    /// 产品是否向 Finder 贡献任何右键菜单项。
    private(set) var isEnabled: Bool

    /// 偏离默认可见状态的功能稳定标识集合。
    private(set) var hiddenFeatureIDs: Set<String>

    /// 全部固定命令的唯一完整排列；隐藏项仍保留其位置。
    private(set) var orderedFeatureIDs: [ContextCommandFeatureID]

    /// 创建产品开关、隐藏功能集合和完整命令排列组成的有效领域配置。
    init(
        isEnabled: Bool = true,
        hiddenFeatureIDs: Set<String> = [],
        orderedFeatureIDs: [ContextCommandFeatureID] = Self.defaultFeatureIDs
    ) {
        precondition(
            orderedFeatureIDs.count == Self.defaultFeatureIDs.count
                && Set(orderedFeatureIDs) == Set(Self.defaultFeatureIDs),
            "Menu ordering must contain every product feature exactly once"
        )
        self.isEnabled = isEnabled
        self.hiddenFeatureIDs = hiddenFeatureIDs
        self.orderedFeatureIDs = orderedFeatureIDs
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

    /// 把一个完整功能移动到指定功能前，nil 表示末尾；返回顺序是否实际变化。
    @discardableResult
    mutating func move(
        _ featureID: ContextCommandFeatureID,
        before nextFeatureID: ContextCommandFeatureID?
    ) -> Bool {
        guard let sourceIndex = orderedFeatureIDs.firstIndex(of: featureID) else {
            preconditionFailure("Only a registered menu feature can be moved")
        }
        let insertionIndex: Int
        if let nextFeatureID {
            guard let index = orderedFeatureIDs.firstIndex(of: nextFeatureID) else {
                preconditionFailure("The insertion target must be a registered menu feature")
            }
            if nextFeatureID == featureID { return false }
            insertionIndex = index
        } else {
            insertionIndex = orderedFeatureIDs.count
        }
        let destinationIndex = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
        guard destinationIndex != sourceIndex else { return false }
        orderedFeatureIDs.remove(at: sourceIndex)
        orderedFeatureIDs.insert(featureID, at: destinationIndex)
        return true
    }

    /// 通过版本化信封恢复领域状态。
    init(from decoder: Decoder) throws {
        self = try CommandMenuSettingsEnvelope(from: decoder).configuration
    }

    /// 把领域状态包装为当前版本信封。
    func encode(to encoder: Encoder) throws {
        try CommandMenuSettingsEnvelope(configuration: self).encode(to: encoder)
    }
}

/// 持久化与传输专用的版本信封；解码后只向业务层交付有效配置。
nonisolated private struct CommandMenuSettingsEnvelope: Codable, Sendable {
    /// 当前持久化和传输格式版本。
    static let currentSchemaVersion = 2

    /// 从当前格式恢复出的有效领域状态。
    let configuration: CommandMenuSettings

    /// 配置持久化和传输使用的稳定字段名。
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case hiddenFeatureIDs
        case orderedFeatureIDs
    }

    /// 使用当前领域状态创建待编码信封。
    init(configuration: CommandMenuSettings) {
        self.configuration = configuration
    }

    /// 只解码字段完整的当前格式。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        guard decodedVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported menu configuration schema"
            )
        }

        let featureIDs = try container.decode([String].self, forKey: .orderedFeatureIDs)
        let expectedIDs = CommandMenuSettings.defaultFeatureIDs.map(\.rawValue)
        guard featureIDs.count == expectedIDs.count, Set(featureIDs) == Set(expectedIDs) else {
            throw DecodingError.dataCorruptedError(
                forKey: .orderedFeatureIDs,
                in: container,
                debugDescription: "Menu ordering must contain every product feature exactly once"
            )
        }
        configuration = CommandMenuSettings(
            isEnabled: try container.decode(
                Bool.self,
                forKey: .isEnabled
            ),
            hiddenFeatureIDs: Set(
                try container.decode(
                    [String].self,
                    forKey: .hiddenFeatureIDs
                )
            ),
            orderedFeatureIDs: featureIDs.map(ContextCommandFeatureID.init(rawValue:))
        )
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
        try container.encode(
            configuration.orderedFeatureIDs.map(\.rawValue),
            forKey: .orderedFeatureIDs
        )
    }
}

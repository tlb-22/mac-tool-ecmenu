import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证菜单配置的有效状态、编解码和格式迁移。
final class MenuConfigurationTests: XCTestCase {
    /// 标准配置默认启用产品菜单。
    func testStandardConfigurationIsEnabled() {
        XCTAssertTrue(MenuConfiguration.standard.isEnabled)
    }

    /// 产品总开关不应覆盖各功能的稀疏隐藏集合。
    func testMasterEnablementPreservesHiddenFeatureIDs() {
        let featureID = CreateNewTextFileCommand.descriptor.id
        var configuration = MenuConfiguration(
            hiddenFeatureIDs: [featureID.rawValue]
        )

        configuration.setEnabled(false)
        XCTAssertFalse(configuration.isEnabled)
        XCTAssertFalse(configuration.isVisible(featureID))
        XCTAssertEqual(configuration.hiddenFeatureIDs, [featureID.rawValue])

        configuration.setEnabled(true)
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertFalse(configuration.isVisible(featureID))
        XCTAssertEqual(configuration.hiddenFeatureIDs, [featureID.rawValue])
    }

    /// 配置只记录隐藏功能，重新显示后恢复标准空集合。
    func testVisibilityUsesOnlyHiddenFeatureIDs() throws {
        let featureID = CreateNewTextFileCommand.descriptor.id
        var configuration = MenuConfiguration.standard
        XCTAssertTrue(configuration.isVisible(featureID))

        configuration.setVisible(false, for: featureID)
        XCTAssertFalse(configuration.isVisible(featureID))
        XCTAssertEqual(configuration.hiddenFeatureIDs, ["new-text-file"])

        configuration.setVisible(true, for: featureID)
        XCTAssertTrue(configuration.isVisible(featureID))
        XCTAssertTrue(configuration.hiddenFeatureIDs.isEmpty)
    }

    /// 当前配置格式应稳定往返并保留未知功能标识。
    func testCurrentFormatRoundTrip() throws {
        let configuration = MenuConfiguration(
            isEnabled: false,
            hiddenFeatureIDs: ["new-text-file", "future-feature"]
        )
        let data = try XCTUnwrap(
            MenuConfigurationChannel.encodedData(for: configuration)
        )
        let decoded = try XCTUnwrap(
            MenuConfigurationChannel.decodedConfiguration(from: data)
        )

        XCTAssertEqual(decoded, configuration)
    }

    /// 已保存的 v2 稀疏隐藏集合应迁移，并默认启用产品菜单。
    func testVersionTwoMigration() throws {
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "hiddenFeatureIDs": ["new-text-file", "future-feature"],
        ])
        let migrated = try XCTUnwrap(
            MenuConfigurationChannel.decodedConfiguration(from: legacyData)
        )

        XCTAssertTrue(migrated.isEnabled)
        XCTAssertEqual(
            migrated.hiddenFeatureIDs,
            ["new-text-file", "future-feature"]
        )
        try assertCurrentSchemaWhenReencoded(migrated)
    }

    /// 已保存的 v1 可见性覆盖应迁移为当前隐藏功能集合。
    func testVersionOneMigration() throws {
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "visibilityOverrides": [
                "new-text-file": false,
                "future-feature": true,
            ],
        ])
        let migrated = try XCTUnwrap(
            MenuConfigurationChannel.decodedConfiguration(from: legacyData)
        )

        XCTAssertTrue(migrated.isEnabled)
        XCTAssertEqual(migrated.hiddenFeatureIDs, ["new-text-file"])
        try assertCurrentSchemaWhenReencoded(migrated)
    }

    /// 不受支持的未来格式不得被误读为默认配置。
    func testUnsupportedSchemaIsRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 999,
            "hiddenFeatureIDs": [],
        ])

        XCTAssertNil(
            MenuConfigurationChannel.decodedConfiguration(from: data)
        )
    }

    /// 迁移后的领域状态再次保存时只产生当前版本信封。
    private func assertCurrentSchemaWhenReencoded(
        _ configuration: MenuConfiguration
    ) throws {
        let data = try XCTUnwrap(
            MenuConfigurationChannel.encodedData(for: configuration)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            object["schemaVersion"] as? Int,
            MenuConfiguration.currentSchemaVersion
        )
    }
}

/**
 验证菜单配置的有效状态、功能可见性和当前格式编解码。
 通过纯值与编码样例检查开关保留隐藏项，以及不完整或不支持格式的拒绝。
 */

import Foundation
import XCTest
@testable import ECMenu

/// 验证菜单配置的有效状态与当前格式编解码。
final class CommandMenuSettingsTests: XCTestCase {
    /// 标准配置默认启用产品菜单。
    func testStandardConfigurationIsEnabled() {
        XCTAssertTrue(CommandMenuSettings.standard.isEnabled)
    }

    /// 产品总开关不应覆盖各功能的稀疏隐藏集合。
    func testMasterEnablementPreservesHiddenFeatureIDs() {
        let featureID = CreateNewFileCommand.descriptor.id
        var configuration = CommandMenuSettings(
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
        let featureID = CreateNewFileCommand.descriptor.id
        var configuration = CommandMenuSettings.standard
        XCTAssertTrue(configuration.isVisible(featureID))

        configuration.setVisible(false, for: featureID)
        XCTAssertFalse(configuration.isVisible(featureID))
        XCTAssertEqual(configuration.hiddenFeatureIDs, ["new-text-file"])

        configuration.setVisible(true, for: featureID)
        XCTAssertTrue(configuration.isVisible(featureID))
        XCTAssertTrue(configuration.hiddenFeatureIDs.isEmpty)
    }

    /// 当前配置格式应稳定往返。
    func testCurrentFormatRoundTrip() throws {
        let configuration = CommandMenuSettings(
            isEnabled: false,
            hiddenFeatureIDs: ["new-text-file"]
        )
        let data = CommandMenuSettingsChannel.encodedData(for: configuration)
        let decoded = try CommandMenuSettingsChannel.decodedConfiguration(
            from: data
        )

        XCTAssertEqual(decoded, configuration)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            object["schemaVersion"] as? Int,
            CommandMenuSettings.currentSchemaVersion
        )
    }

    /// 不受支持的未来格式不得被误读为默认配置。
    func testUnsupportedSchemaIsRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 999,
            "isEnabled": true,
            "hiddenFeatureIDs": [],
        ])

        XCTAssertThrowsError(
            try CommandMenuSettingsChannel.decodedConfiguration(from: data)
        )
    }

    /// 当前 schema 缺少必要字段时不得形成配置。
    func testIncompleteCurrentSchemaIsRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": CommandMenuSettings.currentSchemaVersion,
            "hiddenFeatureIDs": [],
        ])

        XCTAssertThrowsError(
            try CommandMenuSettingsChannel.decodedConfiguration(from: data)
        )
    }
}

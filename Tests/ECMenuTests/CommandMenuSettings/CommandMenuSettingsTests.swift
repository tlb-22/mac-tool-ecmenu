/**
 验证菜单配置的有效状态、功能可见性、命令顺序和当前格式编解码。
 通过纯值与编码样例检查排序保留配置，以及不完整排列和不支持格式的拒绝。
 */

import Foundation
import XCTest
@testable import ECMenu

/// 验证菜单配置的有效状态与当前格式编解码。
final class CommandMenuSettingsTests: XCTestCase {
    /// 标准配置默认启用产品菜单。
    func testStandardConfigurationIsEnabled() {
        XCTAssertTrue(CommandMenuSettings.standard.isEnabled)
        XCTAssertEqual(
            CommandMenuSettings.standard.orderedFeatureIDs.map(\.rawValue),
            ProductContextCommandExpectation.featureIDs
        )
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
            hiddenFeatureIDs: ["new-text-file"],
            orderedFeatureIDs: CommandMenuSettings.defaultFeatureIDs.reversed()
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
        XCTAssertEqual(object["orderedFeatureIDs"] as? [String], configuration.orderedFeatureIDs.map(\.rawValue))
    }

    /// 移动按当前稳定身份计算插入位置，往前、往后和末尾移动均保留隐藏与总开关。
    func testMovesPreserveFeatureIdentityAndVisibility() {
        let ids = CommandMenuSettings.defaultFeatureIDs
        var configuration = CommandMenuSettings(isEnabled: false, hiddenFeatureIDs: [ids[0].rawValue])

        XCTAssertTrue(configuration.move(ids[0], before: ids[3]))
        XCTAssertEqual(configuration.orderedFeatureIDs, [ids[1], ids[2], ids[0]] + Array(ids[3...]))
        XCTAssertTrue(configuration.move(ids[0], before: ids[1]))
        XCTAssertEqual(configuration.orderedFeatureIDs, ids)
        XCTAssertTrue(configuration.move(ids[0], before: nil))
        XCTAssertEqual(configuration.orderedFeatureIDs, Array(ids.dropFirst()) + [ids[0]])
        XCTAssertFalse(configuration.move(ids[0], before: nil))
        XCTAssertFalse(configuration.move(ids[0], before: ids[0]))
        XCTAssertFalse(configuration.move(ids[1], before: ids[2]))
        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.hiddenFeatureIDs, [ids[0].rawValue])
    }

    /// 存储边界拒绝缺项、重复、未知或缺失的顺序，而不是修补为默认排列。
    func testInvalidFeatureOrdersAreRejected() throws {
        let data = CommandMenuSettingsChannel.encodedData(for: .standard)
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ids = CommandMenuSettings.defaultFeatureIDs.map(\.rawValue)
        let invalidOrders = [Array(ids.dropLast()), Array(ids.dropLast()) + [ids[0]], Array(ids.dropLast()) + ["unknown"]]
        for order in invalidOrders {
            var object = valid
            object["orderedFeatureIDs"] = order
            XCTAssertThrowsError(try CommandMenuSettingsChannel.decodedConfiguration(from: JSONSerialization.data(withJSONObject: object)))
        }
        var missing = valid
        missing.removeValue(forKey: "orderedFeatureIDs")
        XCTAssertThrowsError(try CommandMenuSettingsChannel.decodedConfiguration(from: JSONSerialization.data(withJSONObject: missing)))
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

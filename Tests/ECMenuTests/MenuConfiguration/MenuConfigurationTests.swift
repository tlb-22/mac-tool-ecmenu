import Foundation
import XCTest
@testable import ECMenu

/// 验证菜单配置的有效状态与当前格式编解码。
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

    /// 当前配置格式应稳定往返。
    func testCurrentFormatRoundTrip() throws {
        let configuration = MenuConfiguration(
            isEnabled: false,
            hiddenFeatureIDs: ["new-text-file"]
        )
        let data = MenuConfigurationChannel.encodedData(for: configuration)
        let decoded = try MenuConfigurationChannel.decodedConfiguration(
            from: data
        )

        XCTAssertEqual(decoded, configuration)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            object["schemaVersion"] as? Int,
            MenuConfiguration.currentSchemaVersion
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
            try MenuConfigurationChannel.decodedConfiguration(from: data)
        )
    }

    /// 当前 schema 缺少必要字段时不得形成配置。
    func testIncompleteCurrentSchemaIsRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": MenuConfiguration.currentSchemaVersion,
            "hiddenFeatureIDs": [],
        ])

        XCTAssertThrowsError(
            try MenuConfigurationChannel.decodedConfiguration(from: data)
        )
    }
}

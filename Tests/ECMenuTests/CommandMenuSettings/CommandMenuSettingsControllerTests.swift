/**
 验证菜单开关和顺序变更先持久化、再发出菜单失效提示的顺序。
 在通知回调中重读隔离 UserDefaults，检查保存结果并确认无变化操作不重复发布。
 */

import XCTest
@testable import ECMenu

@MainActor
final class CommandMenuSettingsControllerTests: XCTestCase {
    /// 已发布的旧偏好回到产品默认值，读取本身保留原数据且不发布变更。
    func testReleasedConfigurationUsesDefaultsWithoutOverwritingStoredData() throws {
        let suite = "CommandMenuSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let releasedData = Data(#"{"schemaVersion":1,"isEnabled":false,"hiddenFeatureIDs":["new-text-file"]}"#.utf8)
        defaults.set(releasedData, forKey: CommandMenuSettingsChannel.persistedConfigurationKey)
        let store = CommandMenuSettingsStore(defaults: defaults)

        XCTAssertNil(store.load())
        let controller = CommandMenuSettingsController(store: store, publisher: MenuChangePublisher {
            XCTFail("Restoring unsupported preferences must not publish a change")
        })
        XCTAssertEqual(controller.configuration, .standard)
        XCTAssertEqual(defaults.data(forKey: CommandMenuSettingsChannel.persistedConfigurationKey), releasedData)
    }

    func testChangesPersistBeforePublicationAndNoOpDoesNotPublish() throws {
        let suite = "CommandMenuSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CommandMenuSettingsStore(defaults: defaults)
        var published: [CommandMenuSettings] = []
        let controller = CommandMenuSettingsController(store: store, publisher: MenuChangePublisher {
            if let value = store.load() { published.append(value) }
        })

        controller.setVisible(false, for: CreateNewFileCommand.descriptor.id)
        controller.setEnabled(false)
        controller.setEnabled(false)
        controller.setVisible(false, for: CreateNewFileCommand.descriptor.id)
        controller.move(CreateNewFileCommand.descriptor.id, before: nil)
        controller.move(CreateNewFileCommand.descriptor.id, before: nil)
        XCTAssertEqual(published.count, 3)
        XCTAssertEqual(published.last, controller.configuration)
        XCTAssertFalse(controller.configuration.isVisible(CreateNewFileCommand.descriptor.id))
        XCTAssertFalse(controller.configuration.isEnabled)
        XCTAssertEqual(controller.configuration.orderedFeatureIDs.last, CreateNewFileCommand.descriptor.id)

        let restored = CommandMenuSettingsController(store: store, publisher: MenuChangePublisher {
            XCTFail("Restoring preferences must not publish a change")
        })
        XCTAssertEqual(restored.configuration, controller.configuration)
    }
}

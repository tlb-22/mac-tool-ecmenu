/**
 验证菜单开关变更先持久化、再发出菜单失效提示的顺序。
 在通知回调中重读隔离 UserDefaults，检查保存结果并确认无变化操作不重复发布。
 */

import XCTest
@testable import ECMenu

@MainActor
final class CommandMenuSettingsControllerTests: XCTestCase {
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
        XCTAssertEqual(published.count, 2)
        XCTAssertEqual(published.last, controller.configuration)
        XCTAssertFalse(controller.configuration.isVisible(CreateNewFileCommand.descriptor.id))
        XCTAssertFalse(controller.configuration.isEnabled)

        let restored = CommandMenuSettingsController(store: store, publisher: MenuChangePublisher {
            XCTFail("Restoring preferences must not publish a change")
        })
        XCTAssertEqual(restored.configuration, controller.configuration)
    }
}

import AppKit
import XCTest
@testable import ECMenu

@MainActor
final class StatusPageSystemStateTests: XCTestCase {
    /// 应用依赖即使使用系统图标也必须读取，刷新时重新观察安装和扩展状态。
    func testRefreshUsesBusinessDependenciesAndRereadsSystemState() {
        let application = OpenInVSCodeCommand.applicationRequirement
        let descriptor = ContextCommandDescriptor(
            id: "application-with-symbol",
            title: OpenInVSCodeCommand.descriptor.title,
            icon: .systemSymbol(name: "folder"),
            requiredApplication: application
        )
        var installed = false
        var extensionEnabled = false
        var lookupCount = 0
        var iconCount = 0
        let services = StatusPageSystemServices(
            isExtensionEnabled: { extensionEnabled },
            applicationURL: { requirement in
                XCTAssertEqual(requirement, application)
                lookupCount += 1
                return installed ? URL(fileURLWithPath: "/Applications/Code.app") : nil
            },
            applicationIcon: { _ in
                iconCount += 1
                return NSImage(size: NSSize(width: 20, height: 20))
            },
            manageExtension: {},
            openFullDiskAccessSettings: { true }
        )
        let descriptors = [descriptor, OpenInVSCodeCommand.descriptor]
        let missing = services.read(descriptors: descriptors)
        XCTAssertFalse(missing.isExtensionEnabled)
        XCTAssertFalse(missing.isDependencyAvailable(for: descriptor))
        XCTAssertEqual(lookupCount, 1)
        XCTAssertEqual(iconCount, 0)

        installed = true
        extensionEnabled = true
        let available = services.read(descriptors: descriptors)
        XCTAssertTrue(available.isExtensionEnabled)
        XCTAssertTrue(available.isDependencyAvailable(for: descriptor))
        XCTAssertEqual(lookupCount, 2)
        XCTAssertEqual(iconCount, 1)
        XCTAssertFalse(missing.isDependencyAvailable(for: descriptor))
    }

    /// 扩展未启用仍可配置命令；应用缺失和总开关只限制交互，不改变保存值。
    func testConfigurationAvailabilityPreservesSavedVisibility() {
        let application = OpenInVSCodeCommand.applicationRequirement
        let installed = StatusPageSystemState(
            isExtensionEnabled: false,
            applicationIcons: [application.bundleIdentifier: NSImage()]
        )
        let missing = StatusPageSystemState(
            isExtensionEnabled: false,
            applicationIcons: [:]
        )
        let command = OpenInVSCodeCommand.descriptor
        var configuration = MenuConfiguration(
            isEnabled: true,
            hiddenFeatureIDs: [command.id.rawValue]
        )
        XCTAssertTrue(StatusPageContent.isVisibilityEditable(
            for: command, configuration: configuration, systemState: installed
        ))
        XCTAssertFalse(StatusPageContent.isVisibilityEditable(
            for: command, configuration: configuration, systemState: missing
        ))
        XCTAssertTrue(StatusPageContent.isVisibilityEditable(
            for: CopyPathCommand.descriptor,
            configuration: configuration,
            systemState: missing
        ))
        XCTAssertFalse(configuration.isVisible(command.id))
        configuration.setEnabled(false)
        XCTAssertFalse(StatusPageContent.isVisibilityEditable(
            for: command, configuration: configuration, systemState: installed
        ))
        configuration.setEnabled(true)
        XCTAssertTrue(StatusPageContent.isVisibilityEditable(
            for: command, configuration: configuration, systemState: installed
        ))
        XCTAssertFalse(configuration.isVisible(command.id))
    }
}

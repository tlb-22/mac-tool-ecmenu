import AppKit
import FinderSync
import Foundation

/// 状态页一次读取后保留的系统事实，不保存可由这些事实推导的控件状态。
@MainActor
struct StatusPageSystemState {
    let isExtensionEnabled: Bool

    /// 系统可定位的应用及其图标；键的存在同时表示可用性。
    let applicationIcons: [String: NSImage]

    func isDependencyAvailable(for descriptor: ContextCommandDescriptor) -> Bool {
        descriptor.requiredApplication.map {
            applicationIcons[$0.bundleIdentifier] != nil
        } ?? true
    }
}

/// 状态页的 Finder、Launch Services 和系统设置边界。
@MainActor
struct StatusPageSystemServices {
    let isExtensionEnabled: () -> Bool
    let applicationURL: (ContextCommandApplicationRequirement) -> URL?
    let applicationIcon: (URL) -> NSImage
    let manageExtension: () -> Void
    let openFullDiskAccessSettings: () -> Bool

    static let live = StatusPageSystemServices(
        isExtensionEnabled: { FIFinderSyncController.isExtensionEnabled },
        applicationURL: {
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: $0.bundleIdentifier
            )
        },
        applicationIcon: { NSWorkspace.shared.icon(forFile: $0.path) },
        manageExtension: {
            FIFinderSyncController.showExtensionManagementInterface()
        },
        openFullDiskAccessSettings: { FullDiskAccessSettings.open() }
    )

    /// 从业务依赖和视觉图标声明读取需要的应用，每次刷新重新查询系统。
    func read(descriptors: [ContextCommandDescriptor]) -> StatusPageSystemState {
        var applications: [String: ContextCommandApplicationRequirement] = [:]
        for descriptor in descriptors {
            if let application = descriptor.requiredApplication {
                applications[application.bundleIdentifier] = application
            }
            if case .application(let application) = descriptor.icon {
                applications[application.bundleIdentifier] = application
            }
        }

        var icons: [String: NSImage] = [:]
        for application in applications.values {
            if let url = applicationURL(application) {
                icons[application.bundleIdentifier] = applicationIcon(url)
            }
        }
        return StatusPageSystemState(
            isExtensionEnabled: isExtensionEnabled(),
            applicationIcons: icons
        )
    }
}

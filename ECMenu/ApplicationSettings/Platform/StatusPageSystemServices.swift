/**
 读取 Finder 扩展启用状态、依赖应用位置与图标，并提供相关系统设置入口。
 每次刷新根据命令描述查询系统，形成供配置界面消费的事实快照。
 */

import AppKit
import FinderSync

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

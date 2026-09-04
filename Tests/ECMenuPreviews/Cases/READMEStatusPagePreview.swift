import AppKit

/// README 使用的设置页正常运行状态。
@MainActor
private enum READMEStatusPagePreviewState {
    /// 从当前系统严格读取全部外部应用图标，并保持所有产品开关开启。
    static func make() -> StatusPagePreviewState {
        var applicationIcons: [String: NSImage] = [:]

        for descriptor in ContextCommandComposition.handlers.descriptors {
            guard let application = descriptor.requiredApplication else {
                continue
            }
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: application.bundleIdentifier
            ) else {
                preconditionFailure(
                    "README preview requires \(application.displayName) "
                        + "to be installed"
                )
            }

            applicationIcons[application.bundleIdentifier] =
                NSWorkspace.shared.icon(forFile: applicationURL.path)
        }

        return StatusPagePreviewState(
            isExtensionEnabled: true,
            loginItemState: .enabled,
            configuration: MenuConfiguration(
                isEnabled: true,
                hiddenFeatureIDs: []
            ),
            applicationIcons: applicationIcons
        )
    }
}

/// 以正常运行状态呈现 README 中的通用设置页。
@MainActor
enum READMEStatusPageGeneralPreview: ApplicationPreview {
    /// README 图片脚本使用的稳定预览标识。
    static let id = "readme-status-page-general"

    /// 只读取应用安装位置与真实图标，不访问产品偏好或系统设置。
    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .general,
            state: READMEStatusPagePreviewState.make()
        )
    }
}

/// 以正常运行状态呈现 README 中的右键菜单设置页。
@MainActor
enum READMEStatusPageContextMenuPreview: ApplicationPreview {
    /// README 图片脚本使用的稳定预览标识。
    static let id = "readme-status-page-context-menu"

    /// 只读取应用安装位置与真实图标，不访问产品偏好或系统设置。
    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .contextMenu,
            state: READMEStatusPagePreviewState.make()
        )
    }
}

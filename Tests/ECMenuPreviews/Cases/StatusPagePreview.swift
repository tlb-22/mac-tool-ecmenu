import AppKit
import SwiftUI

/// 集中保存主程序设置页预览中需要反复手动调整的场景参数。
@MainActor
private enum StatusPagePreviewParameters {
    /// 预览首次显示的设置分类。
    static let initiallySelectedPane = StatusPagePane.general

    /// 产品总开关的初始状态。
    static let isEnabled = true

    /// Finder Extension 在页面中显示为已启用还是尚未启用。
    static let isExtensionEnabled = false

    /// 登录项在预览中显示的登记与系统批准状态。
    static let loginItemState = LoginItemRegistrationState.requiresApproval

    /// 需要在初始菜单配置中显示为关闭的功能。
    ///
    /// 保持为空可以直观看到 iTerm2 缺失时，开启值被保留但控件不可操作。
    static let initiallyHiddenFeatureIDs: Set<String> = []

    /// 根据集中参数构造只存在于预览进程内的菜单配置。
    static var initialConfiguration: MenuConfiguration {
        MenuConfiguration(
            isEnabled: isEnabled,
            hiddenFeatureIDs: initiallyHiddenFeatureIDs
        )
    }

    /// 为预览中已安装的外部应用创建不依赖 Launch Services 的占位图标。
    static var applicationIcons: [String: NSImage] {
        guard case .application(let application) =
            OpenInVSCodeCommand.descriptor.icon
        else {
            preconditionFailure(
                "VS Code preview command must require an application"
            )
        }
        return [
            application.bundleIdentifier: NSImage(
                systemSymbolName: "app.fill",
                accessibilityDescription: nil
            ) ?? NSImage(),
        ]
    }
}

/// 使用生产 `StatusPageContent` 检查主程序设置页。
@MainActor
enum StatusPagePreview: ApplicationPreview {
    /// `preview-ui.sh` 使用的稳定预览标识。
    static let id = "status-page"

    /// 注入固定状态和内存菜单配置，不访问任何系统设置或偏好存储。
    static func present() -> AnyObject {
        StatusPagePreviewSession()
    }
}

/// 保活真实 SwiftUI 页面所在的标准 AppKit 窗口。
@MainActor
private final class StatusPagePreviewSession {
    /// Preview target 独占的窗口控制器。
    private let windowController: NSWindowController

    /// 用纯状态页面构造自适应内容窗口并立即呈现。
    init() {
        let content = StatusPagePreviewContent()
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = ApplicationMetadata.displayName
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        hostingController.view.layoutSubtreeIfNeeded()
        window.setContentSize(hostingController.view.fittingSize)

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        windowController.showWindow(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// 让 Toggle 只修改 Preview target 的内存快照，其余动作保持为空。
@MainActor
private struct StatusPagePreviewContent: View {
    /// 当前预览会话内的页面选择，不写入产品偏好。
    @State private var selectedPane =
        StatusPagePreviewParameters.initiallySelectedPane

    /// 当前预览会话内的菜单可见性，不读取也不写入产品偏好。
    @State private var configuration =
        StatusPagePreviewParameters.initialConfiguration

    /// 当前预览会话内的登录项状态，不访问 Service Management。
    @State private var loginItemState =
        StatusPagePreviewParameters.loginItemState

    /// 把无副作用状态交给生产呈现层。
    var body: some View {
        StatusPageContent(
            displayName: ApplicationMetadata.displayName,
            version: ApplicationMetadata.version,
            selectedPane: $selectedPane,
            isExtensionEnabled:
                StatusPagePreviewParameters.isExtensionEnabled,
            loginItemState: loginItemState,
            descriptors: ContextCommandComposition.handlers.descriptors,
            configuration: configuration,
            applicationIcons: StatusPagePreviewParameters.applicationIcons,
            setEnabled: { isEnabled in
                configuration.setEnabled(isEnabled)
            },
            setLoginItemRequested: { isRequested in
                loginItemState = isRequested ? .enabled : .notRegistered
            },
            manageExtension: {},
            setVisibility: { isVisible, featureID in
                configuration.setVisible(isVisible, for: featureID)
            },
            openFullDiskAccessSettings: {}
        )
    }
}

import AppKit
import SwiftUI

/// 集中保存主程序设置页状态覆盖预览中需要反复手动调整的场景参数。
@MainActor
private enum StatusPagePreviewParameters {
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

    /// 汇总当前覆盖场景交给共用设置页预览会话。
    static var state: StatusPagePreviewState {
        StatusPagePreviewState(
            isExtensionEnabled: isExtensionEnabled,
            loginItemState: loginItemState,
            configuration: MenuConfiguration(
                isEnabled: isEnabled,
                hiddenFeatureIDs: initiallyHiddenFeatureIDs
            ),
            applicationIcons: applicationIcons
        )
    }
}

/// 使用生产 `StatusPageContent` 检查通用设置页。
@MainActor
enum StatusPageGeneralPreview: ApplicationPreview {
    /// `preview-ui.sh` 使用的稳定预览标识。
    static let id = "status-page-general"

    /// 注入固定状态和内存菜单配置，不访问任何系统设置或偏好存储。
    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .general,
            state: StatusPagePreviewParameters.state
        )
    }
}

/// 使用生产 `StatusPageContent` 检查右键菜单设置页。
@MainActor
enum StatusPageContextMenuPreview: ApplicationPreview {
    /// `preview-ui.sh` 使用的稳定预览标识。
    static let id = "status-page-context-menu"

    /// 注入固定状态和内存菜单配置，不访问任何系统设置或偏好存储。
    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .contextMenu,
            state: StatusPagePreviewParameters.state
        )
    }
}

/// 设置页 Preview 需要注入的完整、无副作用状态。
@MainActor
struct StatusPagePreviewState {
    /// Finder Extension 在页面中显示的启用状态。
    let isExtensionEnabled: Bool

    /// 登录项在页面中显示的登记与批准状态。
    let loginItemState: LoginItemRegistrationState

    /// 产品总开关与各菜单命令的可见性。
    let configuration: MenuConfiguration

    /// 外部应用的可用状态与图标，以 bundle identifier 索引。
    let applicationIcons: [String: NSImage]
}

/// 保活真实 SwiftUI 页面所在的标准 AppKit 窗口。
@MainActor
final class StatusPagePreviewSession {
    /// Preview target 独占的窗口控制器。
    private let windowController: NSWindowController

    /// 用纯状态页面构造自适应内容窗口并立即呈现。
    init(
        selectedPane: StatusPagePane,
        state: StatusPagePreviewState
    ) {
        let content = StatusPagePreviewContent(
            selectedPane: selectedPane,
            state: state
        )
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
    @State private var selectedPane: StatusPagePane

    /// 当前预览会话内的菜单可见性，不读取也不写入产品偏好。
    @State private var configuration: MenuConfiguration

    /// 当前预览会话内的登录项状态，不访问 Service Management。
    @State private var loginItemState: LoginItemRegistrationState

    /// 当前场景显示的 Finder Extension 状态。
    private let isExtensionEnabled: Bool

    /// 当前场景显示的外部应用可用状态与图标。
    private let applicationIcons: [String: NSImage]

    /// 让每个独立预览直接呈现其声明的设置分类。
    init(
        selectedPane: StatusPagePane,
        state: StatusPagePreviewState
    ) {
        _selectedPane = State(initialValue: selectedPane)
        _configuration = State(initialValue: state.configuration)
        _loginItemState = State(initialValue: state.loginItemState)
        isExtensionEnabled = state.isExtensionEnabled
        applicationIcons = state.applicationIcons
    }

    /// 把无副作用状态交给生产呈现层。
    var body: some View {
        StatusPageContent(
            displayName: ApplicationMetadata.displayName,
            version: ApplicationMetadata.version,
            selectedPane: $selectedPane,
            isExtensionEnabled: isExtensionEnabled,
            loginItemState: loginItemState,
            descriptors: ContextCommandComposition.handlers.descriptors,
            configuration: configuration,
            applicationIcons: applicationIcons,
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

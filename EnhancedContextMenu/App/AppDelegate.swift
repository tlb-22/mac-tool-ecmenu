import AppKit
import CoreServices
import OSLog

/// 首次 Open Application Apple Event 表达的进程启动来源。
enum ApplicationInitialOpenSource: Equatable {
    /// 用户或开发工具普通打开了主应用。
    case user

    /// Service Management 在用户登录后启动了主应用。
    case loginItem

    /// 只根据 Open Application 事件携带的登录项枚举恢复启动来源。
    /// - Parameter event: 首次 `kAEOpenApplication` 事件。
    init(openApplicationEvent event: NSAppleEventDescriptor) {
        let launchKind = event.paramDescriptor(
            forKeyword: keyAEPropData
        )?.enumCodeValue
        self = launchKind == keyAELaunchedAsLogInItem
            ? .loginItem
            : .user
    }
}

/// 协调常驻命令宿主与可退出的配置界面生命周期。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 记录无法完成的应用呈现状态切换。
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EnhancedContextMenu",
        category: "ApplicationLifecycle"
    )

    /// 主应用唯一的跨进程右键命令接收器。
    private lazy var contextCommandServer = ContextCommandServer(
        router: ContextCommandRouter(
            handlers: ExecutionComposition.handlers
        ),
        menuConfiguration: menuConfiguration
    )

    /// 配置界面和 Finder Extension 共享的菜单配置真相源。
    private lazy var menuConfiguration = MenuConfigurationController()

    /// 主应用登录项登记与系统批准状态的唯一所有者。
    private lazy var loginItemController = LoginItemController()

    /// 唯一 Status Page 窗口的明确所有者。
    private lazy var statusPageWindowController = StatusPageWindowController(
        menuConfiguration: menuConfiguration,
        loginItemController: loginItemController,
        didClose: { [weak self] in
            self?.handleConfigurationWindowDidClose()
        }
    )

    /// 首次 Open Application 事件是否已经决定了启动呈现形态。
    private var hasHandledInitialOpenApplicationEvent = false

    /// 在 AppKit 处理首次启动事件前接管应用呈现相关 Apple Event。
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(
                handleOpenApplicationEvent(_:withReplyEvent:)
            ),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenApplication)
        )
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(
                handleShowPreferencesEvent(_:withReplyEvent:)
            ),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEShowPreferences)
        )
    }

    /// 装配常驻服务；首次 Open Application 事件随后决定是否显示界面。
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = contextCommandServer
        _ = menuConfiguration
        _ = loginItemController
    }

    /// 让主应用在最后一个窗口关闭后继续接收 Finder 命令。
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    /// 用户再次打开运行中的应用时，始终显示唯一的 Status Page。
    /// - Parameters:
    ///   - sender: 当前应用实例。
    ///   - flag: 是否存在任意可见窗口；业务窗口不影响本方法的决定。
    /// - Returns: `false`，因为本对象已经明确处理重新打开请求。
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showConfiguration()
        return false
    }

    /// 解释首次登录项标记，并把后续打开请求统一视为用户打开配置页。
    /// - Parameters:
    ///   - event: 系统发送的 Open Application Apple Event。
    ///   - replyEvent: AppKit 管理的对应回复事件；当前无需写入结果。
    @objc private func handleOpenApplicationEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        if hasHandledInitialOpenApplicationEvent {
            showConfiguration()
            return
        }

        hasHandledInitialOpenApplicationEvent = true
        if ApplicationInitialOpenSource(
            openApplicationEvent: event
        ) == .loginItem {
            enterBackgroundMode()
        } else {
            showConfiguration()
        }
    }

    /// 把系统标准的“显示设置”事件导向唯一 Status Page。
    /// - Parameters:
    ///   - event: 系统发送的 Show Preferences Apple Event。
    ///   - replyEvent: AppKit 管理的对应回复事件；当前无需写入结果。
    @objc private func handleShowPreferencesEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        showConfiguration()
    }

    // MARK: - ==================== 配置界面呈现边界 ====================

    /// 显示或聚焦唯一的 Status Page，并让应用出现在 Dock 中。
    func showConfiguration() {
        guard changeActivationPolicy(to: .regular) else {
            return
        }
        statusPageWindowController.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 关闭 Status Page 并退出配置形态，但不终止命令宿主或业务任务。
    func hideConfiguration() {
        if !statusPageWindowController.closeWindow() {
            enterBackgroundMode()
        }
    }

    /// 执行标准关闭窗口语义；Status Page 的 delegate 会同步配置会话状态。
    func closeActiveWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    /// 响应用户直接关闭 Status Page 的事件。
    private func handleConfigurationWindowDidClose() {
        enterBackgroundMode()
    }

    /// 把应用切换为无 Dock 图标的 accessory 命令宿主。
    private func enterBackgroundMode() {
        _ = changeActivationPolicy(to: .accessory)
    }

    /// 将 AppKit activation policy 切换为目标值，并记录平台拒绝。
    /// - Parameter policy: 配置会话需要的普通应用或后台配件形态。
    /// - Returns: 已经处于目标状态或本次切换成功时为 `true`。
    private func changeActivationPolicy(
        to policy: NSApplication.ActivationPolicy
    ) -> Bool {
        guard NSApp.activationPolicy() != policy else {
            return true
        }
        guard NSApp.setActivationPolicy(policy) else {
            logger.error(
                "AppKit refused activation policy \(policy.rawValue, privacy: .public)"
            )
            return false
        }
        return true
    }
}

import AppKit
import CoreServices
import XCTest
@testable import ECMenu

/// 验证首次打开事件只根据系统 Property Data 判定启动来源。
final class ApplicationInitialOpenSourceTests: XCTestCase {
    @MainActor
    func testInitialOpenAndLaunchStartIPCOnlyOnceInEitherEventOrder() {
        for openFirst in [true, false] {
            let surface = LifecycleTestSurface()
            let delegate = AppDelegate(effects: surface.effects)
            let finished = Notification(name: NSApplication.didFinishLaunchingNotification)
            if openFirst {
                delegate.handleOpenApplication(source: .user)
                delegate.applicationDidFinishLaunching(finished)
            } else {
                delegate.applicationDidFinishLaunching(finished)
                delegate.handleOpenApplication(source: .user)
            }
            XCTAssertEqual(surface.hostStartRequests, 1)
            XCTAssertEqual(surface.configurationWindow, .visible)
            delegate.handleOpenApplication(source: .user)
            XCTAssertEqual(surface.hostStartRequests, 2)
        }
    }

    @MainActor
    func testLoginStartsHostWithoutShowingConfigurationAndLaterOpenShowsIt() {
        let surface = LifecycleTestSurface()
        let delegate = AppDelegate(effects: surface.effects)
        surface.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.handleOpenApplication(source: .loginItem)
        XCTAssertEqual(surface.hostStartRequests, 1)
        XCTAssertEqual(surface.configurationWindow, .closed)
        XCTAssertEqual(surface.policy, .accessory)
        XCTAssertEqual(surface.activations, 0)

        delegate.handleOpenApplication(source: .user)
        XCTAssertEqual(surface.configurationWindow, .visible)
        XCTAssertEqual(surface.policy, .regular)
        XCTAssertEqual(surface.activations, 1)
        // 首次事件之后即使再次携带登录标记，也属于重新打开配置的请求。
        delegate.handleOpenApplication(source: .loginItem)
        XCTAssertEqual(surface.configurationWindow, .visible)
        XCTAssertEqual(surface.activations, 2)
    }

    @MainActor
    func testMinimizedConfigurationKeepsPolicyAndReopenRestoresWindow() {
        let surface = LifecycleTestSurface()
        let delegate = AppDelegate(effects: surface.effects)
        surface.delegate = delegate
        delegate.handleOpenApplication(source: .user)
        surface.configurationWindow = .minimized
        XCTAssertEqual(surface.policy, .regular)
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
        XCTAssertEqual(surface.configurationWindow, .visible)
        XCTAssertEqual(surface.policy, .regular)

        surface.configurationWindow = .minimized
        delegate.hideConfiguration()
        XCTAssertEqual(surface.configurationWindow, .closed)
        XCTAssertEqual(surface.policy, .accessory)
    }

    @MainActor
    func testQuitClosesConfigurationWhileBusinessWindowRemainsOpen() {
        let surface = LifecycleTestSurface()
        let delegate = AppDelegate(effects: surface.effects)
        surface.delegate = delegate
        delegate.handleOpenApplication(source: .user)
        surface.businessWindowIsOpen = true
        surface.activeWindowIsBusiness = true
        delegate.hideConfiguration() // ECMenuApp 的 Command-Q 入口。
        XCTAssertEqual(surface.configurationWindow, .closed)
        XCTAssertEqual(surface.policy, .accessory)
        XCTAssertTrue(surface.businessWindowIsOpen)
        delegate.hideConfiguration()
        XCTAssertTrue(surface.businessWindowIsOpen)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @MainActor
    func testCloseActiveWindowOnlyEndsConfigurationForItsOwnWindow() {
        let surface = LifecycleTestSurface()
        let delegate = AppDelegate(effects: surface.effects)
        surface.delegate = delegate
        delegate.handleOpenApplication(source: .user)
        surface.businessWindowIsOpen = true
        surface.activeWindowIsBusiness = true
        delegate.closeActiveWindow()
        XCTAssertFalse(surface.businessWindowIsOpen)
        XCTAssertEqual(surface.configurationWindow, .visible)
        XCTAssertEqual(surface.policy, .regular)

        surface.activeWindowIsBusiness = false
        delegate.closeActiveWindow()
        XCTAssertEqual(surface.configurationWindow, .closed)
        XCTAssertEqual(surface.policy, .accessory)
    }

    @MainActor
    func testRejectedActivationPolicyDoesNotShowConfiguration() {
        let surface = LifecycleTestSurface()
        surface.acceptsPolicyChanges = false
        let delegate = AppDelegate(effects: surface.effects)
        delegate.handleOpenApplication(source: .user)
        XCTAssertEqual(surface.configurationWindow, .closed)
        XCTAssertEqual(surface.activations, 0)
    }

    /// 登录项枚举只有位于 Property Data 参数中时才表达登录启动。
    func testInitialOpenSourceUsesPropertyDataLoginItemEnumeration() {
        let userEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        let loginItemEvent = userEvent.copy() as! NSAppleEventDescriptor
        loginItemEvent.setParam(
            NSAppleEventDescriptor(
                enumCode: keyAELaunchedAsLogInItem
            ),
            forKeyword: keyAEPropData
        )

        XCTAssertEqual(
            ApplicationInitialOpenSource(
                openApplicationEvent: userEvent
            ),
            .user
        )
        XCTAssertEqual(
            ApplicationInitialOpenSource(
                openApplicationEvent: loginItemEvent
            ),
            .loginItem
        )
    }

    /// Property Data 中的其他启动枚举不能被误判为登录项启动。
    func testInitialOpenSourceRejectsOtherPropertyDataEnumeration() {
        let serviceItemEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        serviceItemEvent.setParam(
            NSAppleEventDescriptor(
                enumCode: keyAELaunchedAsServiceItem
            ),
            forKeyword: keyAEPropData
        )

        XCTAssertEqual(
            ApplicationInitialOpenSource(
                openApplicationEvent: serviceItemEvent
            ),
            .user
        )
    }
}

/// 只替换 AppKit 的窗口事实和副作用；事件判定与呈现编排仍执行 AppDelegate。
@MainActor
private final class LifecycleTestSurface {
    enum WindowState { case closed, visible, minimized }
    weak var delegate: AppDelegate?
    var configurationWindow = WindowState.closed
    var businessWindowIsOpen = false
    var activeWindowIsBusiness = false
    var policy = NSApplication.ActivationPolicy.accessory
    var acceptsPolicyChanges = true
    var hostStartRequests = 0
    var activations = 0

    var effects: ApplicationLifecycleEffects {
        ApplicationLifecycleEffects(
            startIPC: { self.hostStartRequests += 1 },
            changeActivationPolicy: { policy in
                guard self.acceptsPolicyChanges else { return false }
                self.policy = policy
                return true
            },
            showConfigurationWindow: { self.configurationWindow = .visible },
            closeConfigurationWindow: { self.closeConfiguration() },
            closeActiveWindow: {
                if self.activeWindowIsBusiness {
                    self.businessWindowIsOpen = false
                } else {
                    _ = self.closeConfiguration()
                }
            },
            activate: { self.activations += 1 }
        )
    }

    private func closeConfiguration() -> Bool {
        guard configurationWindow != .closed else { return false }
        configurationWindow = .closed
        delegate?.handleConfigurationWindowDidClose()
        return true
    }
}

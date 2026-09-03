import AppKit
import SwiftUI

/// 明确拥有应用唯一的 Status Page 窗口。
@MainActor
final class StatusPageWindowController: NSObject, NSWindowDelegate {
    /// 状态页窗口在系统自动保存位置时使用的稳定名称。
    private static let frameAutosaveName = "ECMenu.StatusPage"

    /// 用户关闭状态页后通知应用退出配置形态。
    private let didClose: () -> Void

    /// 可重复关闭和重开的唯一窗口实例。
    private let window: NSWindow

    /// 创建并配置不可缩放的 SwiftUI 状态页窗口。
    /// - Parameters:
    ///   - menuConfiguration: 状态页使用的菜单配置真相源。
    ///   - loginItemController: 状态页使用的登录项系统状态真相源。
    ///   - didClose: 用户或应用关闭该窗口后的生命周期回调。
    init(
        menuConfiguration: MenuConfigurationController,
        loginItemController: LoginItemController,
        didClose: @escaping () -> Void
    ) {
        self.didClose = didClose

        let hostingController = NSHostingController(
            rootView: StatusPage()
                .environmentObject(menuConfiguration)
                .environmentObject(loginItemController)
        )
        hostingController.view.layoutSubtreeIfNeeded()

        let window = NSWindow(contentViewController: hostingController)
        window.title = ApplicationMetadata.displayName
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(hostingController.view.fittingSize)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        self.window = window

        super.init()

        window.delegate = self
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
    }

    /// 显示、反最小化并聚焦已有的唯一窗口。
    func showWindow() {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// 关闭可见的状态页；关闭回调负责同步呈现状态。
    /// - Returns: 本次调用确实发起窗口关闭时为 `true`。
    @discardableResult
    func closeWindow() -> Bool {
        guard window.isVisible || window.isMiniaturized else {
            return false
        }
        window.close()
        return true
    }

    /// 精确监听 Status Page 关闭，而不受其他业务窗口影响。
    func windowWillClose(_ notification: Notification) {
        didClose()
    }
}

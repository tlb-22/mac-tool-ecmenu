/**
 延迟创建并持有唯一配置窗口与 SwiftUI 宿主，管理显示、关闭和位置恢复。
 向宿主注入共享业务控制器，并把原生关闭事件回传应用生命周期。
 */

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
    private var window: NSWindow?
    private let makeContent: () -> NSViewController

    /// 创建并配置不可缩放的 SwiftUI 状态页窗口。
    /// - Parameters:
    ///   - commandMenuSettings: 状态页使用的菜单配置真相源。
    ///   - loginItemController: 状态页使用的登录项系统状态真相源。
    ///   - newFileTemplates: 状态页使用的模板库控制器。
    ///   - didClose: 用户或应用关闭该窗口后的生命周期回调。
    init(
        commandMenuSettings: CommandMenuSettingsController,
        loginItemController: LoginItemController,
        newFileTemplates: FileTemplateController,
        descriptors: [ContextCommandDescriptor],
        systemServices: StatusPageSystemServices,
        didClose: @escaping () -> Void
    ) {
        self.didClose = didClose

        makeContent = {
            let hostingController = NSHostingController(
                rootView: StatusPage(descriptors: descriptors, systemServices: systemServices)
                    .environmentObject(commandMenuSettings)
                    .environmentObject(loginItemController)
                    .environmentObject(newFileTemplates)
            )
            hostingController.view.layoutSubtreeIfNeeded()
            return hostingController
        }
        super.init()
    }

    /// 首次显示时创建窗口；登录启动只装配服务，不提前创建设置控件与模板编辑会话。
    private func configurationWindow() -> NSWindow {
        if let window { return window }
        let content = makeContent()
        let window = NSWindow(contentViewController: content)
        window.title = ApplicationMetadata.displayName
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(content.view.fittingSize)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        window.delegate = self
        if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        self.window = window
        return window
    }

    /// 显示、反最小化并聚焦已有的唯一窗口。
    func showWindow() {
        let window = configurationWindow()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// 关闭可见的状态页；关闭回调负责同步呈现状态。
    /// - Returns: 本次调用确实发起窗口关闭时为 `true`。
    @discardableResult
    func closeWindow() -> Bool {
        guard let window, window.isVisible || window.isMiniaturized else {
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

import SwiftUI

/// ECMenu 主应用的 SwiftUI 入口与依赖装配点。
@main
struct ECMenuApp: App {
    /// 桥接 AppKit 生命周期、常驻命令宿主和配置窗口。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// SwiftUI 保留应用菜单；Status Page 的唯一窗口由 AppDelegate 明确管理。
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(
                    LocalizedStringResource(
                        "common.settings",
                        defaultValue: "Settings…",
                        comment: "Button or menu item that opens settings"
                    )
                ) {
                    appDelegate.showConfiguration()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(before: .windowSize) {
                Button(
                    LocalizedStringResource(
                        "app.menu.closeWindow",
                        defaultValue: "Close Window",
                        comment: "Application menu command that closes the active window"
                    )
                ) {
                    appDelegate.closeActiveWindow()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button(
                    LocalizedStringResource(
                        "app.menu.quit",
                        defaultValue: "Quit \(ApplicationMetadata.displayName)",
                        comment: "Application menu command that leaves the settings interface"
                    )
                ) {
                    appDelegate.hideConfiguration()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

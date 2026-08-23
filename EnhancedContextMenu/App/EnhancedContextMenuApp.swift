import SwiftUI

/// ECMenu 主应用的 SwiftUI 入口与依赖装配点。
@main
struct EnhancedContextMenuApp: App {
    /// 桥接 AppKit 生命周期、常驻命令宿主和配置窗口。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// SwiftUI 保留应用菜单；Status Page 的唯一窗口由 AppDelegate 明确管理。
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    appDelegate.showConfiguration()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(before: .windowSize) {
                Button("关闭窗口") {
                    appDelegate.closeActiveWindow()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button("退出 \(ApplicationMetadata.displayName)") {
                    appDelegate.hideConfiguration()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

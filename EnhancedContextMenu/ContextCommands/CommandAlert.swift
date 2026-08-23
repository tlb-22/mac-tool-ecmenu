import AppKit
import Foundation

/// 命令失败时交给统一呈现器的纯界面内容。
nonisolated struct CommandAlertContent: Equatable, Sendable {
    /// 所有命令错误弹窗共用的标题。
    let title: String

    /// 只描述操作与简要原因的正文。
    let body: String

    init(body: String) {
        title = "操作未完成"
        self.body = body
    }
}

/// 构造命令错误正文中一致的对象名称或数量。
nonisolated enum CommandAlertText {
    /// 单个对象显示名称，多个对象显示数量和量词。
    static func subject(for urls: [URL], countedAs counter: String) -> String {
        precondition(!urls.isEmpty)

        guard urls.count == 1, let url = urls.first else {
            return "\(urls.count) \(counter)"
        }
        return "“\(displayName(for: url))”"
    }

    /// 使用末级名称，避免把完整路径暴露到错误弹窗。
    private static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? "/" : name
    }
}

/// 只负责把已经构造好的内容显示为标准命令错误弹窗。
@MainActor
enum CommandAlertPresenter {
    static func present(_ content: CommandAlertContent) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = content.title
        alert.informativeText = content.body
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

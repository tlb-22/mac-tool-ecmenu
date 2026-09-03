import AppKit
import Foundation

/// 命令失败时交给统一呈现器的纯界面内容。
nonisolated struct CommandAlertContent: Equatable, Sendable {
    /// 所有命令错误弹窗共用的标题。
    let title: String

    /// 只描述操作与简要原因的正文。
    let body: String

    init(body: String, locale: Locale = .current) {
        title = String(
            localized: LocalizedStringResource(
                "alert.command.title",
                defaultValue: "Operation Couldn’t Be Completed",
                locale: locale,
                comment: "Title shared by context-command error alerts"
            )
        )
        self.body = body
    }
}

/// 错误正文引用一个具体对象，或汇总两个及以上对象。
nonisolated enum CommandAlertSubject: Equatable, Sendable {
    case named(String)
    case counted(Int)
}

/// 从失败对象构造不包含语言片段的稳定主语事实。
nonisolated enum CommandAlertText {
    /// 单个对象保留名称，多个对象只保留数量。
    static func subject(for urls: [URL]) -> CommandAlertSubject {
        precondition(!urls.isEmpty)

        guard urls.count == 1, let url = urls.first else {
            return .counted(urls.count)
        }
        return .named(displayName(for: url))
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
        alert.addButton(
            withTitle: String(
                localized: LocalizedStringResource(
                    "alert.command.confirm",
                    defaultValue: "OK",
                    comment: "Dismisses a context-command error alert"
                )
            )
        )

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

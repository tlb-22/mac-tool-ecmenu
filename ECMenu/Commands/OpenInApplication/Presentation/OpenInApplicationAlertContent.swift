/**
 为外部应用打开失败生成本地化告警内容。
 按目标不可用、应用缺失和启动失败等原因组织用户说明。
 */

import Foundation

/// 外部应用失败只保留稳定的命令级说明。
nonisolated enum OpenInApplicationAlertContent {
    static func make(
        for outcome: OpenInApplicationOutcome,
        applicationName: String,
        locale: Locale = .current
    ) -> CommandAlertContent? {
        guard case .failed = outcome else {
            return nil
        }
        let body = String(
            localized: LocalizedStringResource(
                "alert.openInApplication.failed",
                defaultValue: "Couldn’t open in \(applicationName).",
                locale: locale,
                comment: "A selected item could not be opened in the named external application"
            )
        )
        return CommandAlertContent(body: body, locale: locale)
    }
}

/**
 根据显示隐藏的批次问题生成本地化告警内容。
 将文件系统原因与受影响目标组织为用户可理解的说明。
 */

import Foundation

/// 把权限和只读问题合并为统一的写入权限文案。
nonisolated enum VisibilityAlertContent {
    /// 区分整批失败与保留了成功结果的部分失败。
    private enum FailureScope {
        case all
        case partial
    }

    static func make(
        for report: VisibilityReport,
        operation: VisibilityOperation,
        locale: Locale = .current
    ) -> CommandAlertContent? {
        let writePermissionIssues = report.issues.filter {
            $0.kind == .permissionDenied || $0.kind == .readOnlyFileSystem
        }
        guard !writePermissionIssues.isEmpty else {
            return nil
        }

        let subject = CommandAlertText.subject(
            for: writePermissionIssues.map(\.itemURL)
        )
        let scope: FailureScope = report.succeededCount > 0 ? .partial : .all
        let body = localizedBody(
            operation: operation,
            scope: scope,
            subject: subject,
            locale: locale
        )
        return CommandAlertContent(
            body: body,
            locale: locale
        )
    }

    /// 每种语义组合使用完整句式，避免依赖任一语言的词序。
    private static func localizedBody(
        operation: VisibilityOperation,
        scope: FailureScope,
        subject: CommandAlertSubject,
        locale: Locale
    ) -> String {
        let resource: LocalizedStringResource
        switch (operation, scope, subject) {
        case (.hide, .all, .named(let name)):
            resource = LocalizedStringResource(
                "alert.visibility.hide.all.named",
                defaultValue: "Couldn’t hide “\(name)” because it isn’t writable.",
                locale: locale,
                comment: "The named selected item could not be hidden because it is not writable"
            )
        case (.hide, .all, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.visibility.hide.all.counted",
                defaultValue: "Couldn’t hide the selected items because \(count) items aren’t writable.",
                locale: locale,
                comment: "No selected items could be hidden; the argument is the number of unwritable items"
            )
        case (.hide, .partial, .named(let name)):
            resource = LocalizedStringResource(
                "alert.visibility.hide.partial.named",
                defaultValue: "Some items couldn’t be hidden because “\(name)” isn’t writable.",
                locale: locale,
                comment: "Other selected items were hidden, but the named item is not writable"
            )
        case (.hide, .partial, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.visibility.hide.partial.counted",
                defaultValue: "Some items couldn’t be hidden because \(count) items aren’t writable.",
                locale: locale,
                comment: "Other selected items were hidden; the argument is the number of unwritable items"
            )
        case (.show, .all, .named(let name)):
            resource = LocalizedStringResource(
                "alert.visibility.show.all.named",
                defaultValue: "Couldn’t show “\(name)” because it isn’t writable.",
                locale: locale,
                comment: "The named selected item could not be shown because it is not writable"
            )
        case (.show, .all, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.visibility.show.all.counted",
                defaultValue: "Couldn’t show the selected items because \(count) items aren’t writable.",
                locale: locale,
                comment: "No selected items could be shown; the argument is the number of unwritable items"
            )
        case (.show, .partial, .named(let name)):
            resource = LocalizedStringResource(
                "alert.visibility.show.partial.named",
                defaultValue: "Some items couldn’t be shown because “\(name)” isn’t writable.",
                locale: locale,
                comment: "Other selected items were shown, but the named item is not writable"
            )
        case (.show, .partial, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.visibility.show.partial.counted",
                defaultValue: "Some items couldn’t be shown because \(count) items aren’t writable.",
                locale: locale,
                comment: "Other selected items were shown; the argument is the number of unwritable items"
            )
        }
        return String(localized: resource)
    }
}

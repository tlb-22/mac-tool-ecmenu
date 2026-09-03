import AppKit
import Foundation
import OSLog

// MARK: - ==================== 类型化计划与结果 ====================

/// 隐藏属性需要达到的最终状态。
nonisolated enum VisibilityOperation: String, Equatable, Sendable {
    /// 设置 macOS 文件隐藏属性。
    case hide

    /// 清除 macOS 文件隐藏属性。
    case show

    /// 写入 `URLResourceValues.isHidden` 的最终值。
    var isHidden: Bool { self == .hide }

}

/// 描述一次隐藏属性写入所需的不可变执行计划。
nonisolated struct VisibilityPlan: Equatable, Sendable {
    /// 本次命令要求达到的最终隐藏状态。
    let operation: VisibilityOperation

    /// 不包含点号名称、保持 Finder 选择顺序的对象。
    let itemURLs: [URL]
}

/// 一项没有完成的隐藏属性操作。
nonisolated struct VisibilityIssue: Equatable, Sendable {
    /// 没有完成属性写入的对象。
    let itemURL: URL

    /// 底层系统错误的稳定快照。
    let systemError: SystemErrorSnapshot

    /// 从唯一底层错误事实推导出的反馈类别。
    var kind: FileSystemErrorKind {
        FileSystemErrorKind(classifying: systemError)
    }
}

/// 批量隐藏或显示结束后的完整事实。
nonisolated struct VisibilityReport: Equatable, Sendable {
    /// 成功达到目标状态的普通名称对象数量。
    let succeededCount: Int

    /// 所有失败项目；成功项目不回滚。
    let issues: [VisibilityIssue]
}

// MARK: - ==================== 主应用功能 Handler ====================

/// 把共享命令类型静态绑定到需要达到的隐藏状态。
nonisolated protocol VisibilityCommand: ContextCommandPayload {
    /// 命令携带的非空 Finder 选择。
    var selection: FinderItemSelection { get }

    /// 该命令要求的固定操作。
    static var operation: VisibilityOperation { get }
}

extension HideItemsCommand: VisibilityCommand {
    static var operation: VisibilityOperation { .hide }
}

extension ShowItemsCommand: VisibilityCommand {
    static var operation: VisibilityOperation { .show }
}

/// 使用具体命令类型决定隐藏或显示的共享 Handler。
@MainActor
struct VisibilityHandler<Command: VisibilityCommand>: ContextCommandHandling {
    /// 在通用执行器中逐项写入隐藏属性。
    @concurrent nonisolated func execute(
        _ command: Command
    ) async -> VisibilityReport {
        VisibilityExecution.execute(
            selection: command.selection,
            operation: Command.operation
        )
    }

    /// 使用命令类型绑定的操作呈现统一反馈。
    func present(_ report: VisibilityReport, requestID: UUID) {
        VisibilityFeedback.present(
            report,
            operation: Command.operation,
            requestID: requestID
        )
    }
}

typealias HideItemsHandler = VisibilityHandler<HideItemsCommand>
typealias ShowItemsHandler = VisibilityHandler<ShowItemsCommand>

// MARK: - ==================== 执行管线：副作用 - 纯函数 - 副作用 ====================

/// 组合 Finder 目标解析、计划构造和逐项隐藏属性写入。
nonisolated enum VisibilityExecution {
    /// 顺序执行完整可见性操作；调用方负责执行隔离。
    static func execute(
        selection: FinderItemSelection,
        operation: VisibilityOperation
    ) -> VisibilityReport {
        let plan = makePlan(
            operation: operation,
            itemURLs: selection.urls
        )
        return execute(plan)
    }

    // MARK: - ==================== 纯函数：构造执行计划 ====================

    /// 过滤不能通过隐藏属性显示的点号名称，并形成最终执行计划。
    static func makePlan(
        operation: VisibilityOperation,
        itemURLs: [URL]
    ) -> VisibilityPlan {
        return VisibilityPlan(
            operation: operation,
            itemURLs: itemURLs.filter { !isDotItem($0) }
        )
    }

    /// 判断对象是否由点号名称天然决定为隐藏。
    static func isDotItem(_ itemURL: URL) -> Bool {
        itemURL.lastPathComponent.hasPrefix(".")
    }

    // MARK: - ==================== 副作用：执行计划并分类错误 ====================

    /// 逐项设置隐藏属性，保留全部成功并收集失败。
    static func execute(_ plan: VisibilityPlan) -> VisibilityReport {
        var succeededCount = 0
        var issues: [VisibilityIssue] = []

        for itemURL in plan.itemURLs {
            guard !Task.isCancelled else {
                break
            }

            do {
                var values = URLResourceValues()
                values.isHidden = plan.operation.isHidden
                var mutableURL = itemURL
                try mutableURL.setResourceValues(values)
                succeededCount += 1
            } catch {
                issues.append(issue(for: error, itemURL: itemURL))
            }
        }

        return VisibilityReport(
            succeededCount: succeededCount,
            issues: issues
        )
    }

    /// 将系统错误映射为决定批量反馈策略的稳定问题。
    static func issue(for error: Error, itemURL: URL) -> VisibilityIssue {
        let systemError = SystemErrorSnapshot(capturing: error)
        return VisibilityIssue(
            itemURL: itemURL,
            systemError: systemError
        )
    }
}

// MARK: - ==================== 纯函数：构造错误提示内容 ====================

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

// MARK: - ==================== 副作用：汇总日志与用户反馈 ====================

/// 把批量可见性结果编排为一次日志记录和一次用户反馈。
@MainActor
private enum VisibilityFeedback {
    /// 成功静默；权限和只读问题弹窗；其他失败只响一次提示音。
    static func present(
        _ report: VisibilityReport,
        operation: VisibilityOperation,
        requestID: UUID
    ) {
        VisibilityOutcomeLogger.log(
            report,
            operation: operation,
            requestID: requestID
        )

        guard !report.issues.isEmpty else {
            return
        }
        if let content = VisibilityAlertContent.make(
            for: report,
            operation: operation
        ) {
            CommandAlertPresenter.present(content)
        } else {
            NSSound.beep()
        }
    }
}

/// 只记录隐藏与显示的详细结果，不构造或显示弹窗。
@MainActor
private enum VisibilityOutcomeLogger {
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "Visibility"
    )

    static func log(
        _ report: VisibilityReport,
        operation: VisibilityOperation,
        requestID: UUID
    ) {
        for issue in report.issues {
            logger.error(
                "Visibility failure for \(operation.rawValue, privacy: .public) request \(requestID.uuidString, privacy: .public) at \(issue.itemURL.path, privacy: .private) [\(issue.systemError.domain, privacy: .public):\(issue.systemError.code, privacy: .public)]: \(issue.systemError.localizedDescription, privacy: .private)"
            )
        }
        if report.issues.isEmpty {
            logger.info(
                "Completed \(operation.rawValue, privacy: .public) request \(requestID.uuidString, privacy: .public) for \(report.succeededCount) items"
            )
        }
    }
}

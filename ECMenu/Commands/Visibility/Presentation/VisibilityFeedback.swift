/**
 呈现显示隐藏操作的批次结果并记录逐项诊断。
 按成功数量和失败原因选择反馈内容，关联本次命令请求身份。
 */

import AppKit
import Foundation
import OSLog

/// 把批量可见性结果编排为一次日志记录和一次用户反馈。
@MainActor
enum VisibilityFeedback {
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

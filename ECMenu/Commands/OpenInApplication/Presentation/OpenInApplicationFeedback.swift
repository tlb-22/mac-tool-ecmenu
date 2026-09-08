/**
 呈现在外部应用中打开的执行结果并记录诊断信息。
 将命令要求和请求身份用于可关联的用户反馈与日志。
 */

import AppKit
import Foundation
import OSLog

/// 把外部应用打开结果编排为一次日志记录和一次错误反馈。
@MainActor
enum OpenInApplicationFeedback {
    static func present(
        _ outcome: OpenInApplicationOutcome,
        applicationName: String,
        requestID: UUID
    ) {
        OpenInApplicationOutcomeLogger.log(outcome, requestID: requestID)
        if let content = OpenInApplicationAlertContent.make(
            for: outcome,
            applicationName: applicationName
        ) {
            CommandAlertPresenter.present(content)
        }
    }
}

/// 只记录外部应用打开的详细结果，不构造或显示弹窗。
@MainActor
private enum OpenInApplicationOutcomeLogger {
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "OpenInApplication"
    )

    static func log(
        _ outcome: OpenInApplicationOutcome,
        requestID: UUID
    ) {
        switch outcome {
        case .succeeded(let plan):
            logger.info(
                "Opened target with \(plan.application.displayName, privacy: .public) for request \(requestID.uuidString, privacy: .public)"
            )

        case .failed(.targetUnavailable):
            logger.error(
                "External-application target unavailable for request \(requestID.uuidString, privacy: .public)"
            )

        case .failed(.applicationUnavailable(let application)):
            logger.error(
                "Application \(application.bundleIdentifier, privacy: .public) unavailable for request \(requestID.uuidString, privacy: .public)"
            )

        case .failed(.launchFailed(let plan, let systemError)):
            logger.error(
                "Could not open target with \(plan.application.displayName, privacy: .public) for request \(requestID.uuidString, privacy: .public) at \(plan.targetURL.path, privacy: .private) [\(systemError.domain, privacy: .public):\(systemError.code, privacy: .public)]: \(systemError.localizedDescription, privacy: .private)"
            )
        }
    }
}

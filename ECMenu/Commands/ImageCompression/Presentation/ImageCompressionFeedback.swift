/**
 将压缩结果编排为 Finder 输出文件选择、日志和必要的失败提示。
 用请求身份关联逐项诊断，并根据批次问题选择告警或提示音。
 */

import AppKit
import Foundation
import OSLog

// MARK: - ==================== 副作用：选择结果、日志与用户反馈 ====================

/// 把压缩结果编排为 Finder 选择、一次日志记录和一次用户反馈。
@MainActor
enum ImageCompressionFeedback {
    static func present(
        _ outcome: ImageCompressionOutcome,
        requestID: UUID
    ) {
        ImageCompressionOutcomeLogger.log(outcome, requestID: requestID)

        switch outcome {
        case .cancelled:
            return

        case .completed(let report):
            if !report.outputURLs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(
                    report.outputURLs
                )
            }
            guard report.hasIssues else {
                return
            }
            if let content = ImageCompressionAlertContent.make(for: report) {
                CommandAlertPresenter.present(content)
            } else {
                NSSound.beep()
            }
        }
    }
}

/// 只记录图片压缩的详细执行事实，不构造或显示弹窗。
@MainActor
private enum ImageCompressionOutcomeLogger {
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "ImageCompression"
    )

    static func log(
        _ outcome: ImageCompressionOutcome,
        requestID: UUID
    ) {
        switch outcome {
        case .cancelled:
            logger.debug(
                "Cancelled image-compression request \(requestID.uuidString, privacy: .public)"
            )

        case .completed(let report):
            for failure in report.failures {
                logFailure(
                    stage: failure.stageName,
                    sourceURL: failure.sourceURL,
                    locationURL: failure.locationURL,
                    error: failure.systemError,
                    requestID: requestID
                )
            }
            for output in report.outputs {
                if let error = output.fileDateError {
                    logFailure(
                        stage: "fileDates",
                        sourceURL: output.url,
                        locationURL: output.url,
                        error: error,
                        requestID: requestID
                    )
                }
            }
            guard !report.hasIssues else {
                return
            }
            if report.wasCancelled {
                logger.info(
                    "Cancelled image compression after \(report.outputURLs.count) outputs for request \(requestID.uuidString, privacy: .public)"
                )
            } else {
                logger.info(
                    "Compressed \(report.outputURLs.count) images for request \(requestID.uuidString, privacy: .public)"
                )
            }
        }
    }

    /// 日志保留受影响图片与失败位置；用户正文只引用图片名称。
    private static func logFailure(
        stage: String,
        sourceURL: URL,
        locationURL: URL,
        error: SystemErrorSnapshot,
        requestID: UUID
    ) {
        logger.error(
            "Image-compression failure during \(stage, privacy: .public) for request \(requestID.uuidString, privacy: .public), image \(sourceURL.path, privacy: .private), location \(locationURL.path, privacy: .private) [\(error.domain, privacy: .public):\(error.code, privacy: .public)]: \(error.localizedDescription, privacy: .private)"
        )
    }
}

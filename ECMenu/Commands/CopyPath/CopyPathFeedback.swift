/**
 把复制路径的执行结果转换为日志与用户反馈。
 在反馈边界处理失败和取消结果，并保留请求身份供诊断关联。
 */

import AppKit
import Foundation
import OSLog

@MainActor
enum CopyPathFeedback {
    private static let logger = Logger(subsystem: ApplicationLogging.subsystem, category: "CopyPath")

    static func present(_ outcome: CopyPathOutcome, requestID: UUID) {
        switch outcome {
        case .cancelled:
            return
        case .success(let success):
            logger.info("Copied \(success.itemCount) paths for request \(requestID.uuidString, privacy: .public)")
        case .failure(.targetUnavailable):
            logger.error("Could not resolve paths for copy-path request \(requestID.uuidString, privacy: .public)")
            NSSound.beep()
        case .failure(.pasteboardWriteFailed):
            logger.error("Could not write copy-path request \(requestID.uuidString, privacy: .public) to the pasteboard")
            NSSound.beep()
        }
    }
}

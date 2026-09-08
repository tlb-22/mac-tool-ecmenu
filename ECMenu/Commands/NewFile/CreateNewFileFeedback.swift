/**
 把新建文件的成功或失败结果转换为用户反馈与诊断日志。
 成功时请求 Finder 选中新文件；目标目录权限问题生成告警，其余失败使用提示音。
 */

import AppKit
import Foundation
import OSLog

@MainActor
enum CreateNewFileFeedback {
    static func present(_ outcome: CreateNewFileOutcome, requestID: UUID) {
        switch outcome {
        case .success(let success):
            if !NSWorkspace.shared.selectFile(success.fileURL.path, inFileViewerRootedAtPath: "") {
                Self.logger.error("Finder could not select created file for request \(requestID)")
            }
            Self.logger.info(
                "Created file for request \(requestID) in \(success.elapsedMilliseconds) ms at \(success.fileURL.path, privacy: .private)"
            )
        case .failure(let failure):
            Self.logger.error(
                "File creation failed for request \(requestID): \(String(describing: failure), privacy: .private)"
            )
            if let content = CreateNewFileAlertContent.make(for: failure) {
                CommandAlertPresenter.present(content)
            } else {
                NSSound.beep()
            }
        }
    }

    private static let logger = Logger(subsystem: ApplicationLogging.subsystem, category: "NewFile")
}

/// 仅把目标目录写入失败映射为目录不可写说明。
nonisolated enum CreateNewFileAlertContent {
    static func make(
        for failure: CreateNewFileFailure,
        locale: Locale = .current
    ) -> CommandAlertContent? {
        guard case .destination(let directoryURL, let systemError) = failure else { return nil }
        switch FileSystemErrorKind(classifying: systemError) {
        case .permissionDenied, .readOnlyFileSystem: break
        case .unavailable, .other: return nil
        }
        guard case .named(let directoryName) = CommandAlertText.subject(for: [directoryURL]) else {
            preconditionFailure("A new file has exactly one destination directory")
        }
        return CommandAlertContent(body: String(localized: LocalizedStringResource(
            "alert.newFile.writePermission.named",
            defaultValue: "Couldn’t create a file because “\(directoryName)” isn’t writable.",
            locale: locale,
            comment: "A file could not be created in the named directory because it is not writable"
        )), locale: locale)
    }
}

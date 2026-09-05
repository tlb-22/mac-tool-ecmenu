import AppKit
import Foundation
import OSLog

/// 把压缩失败与已经生成 JPG 后的时间属性问题分别汇总。
nonisolated enum ImageCompressionAlertContent {
    /// 区分问题是否只影响已处理图片中的一部分。
    private enum IssueScope {
        case all
        case partial
    }

    private enum AccessFailure {
        case read
        case write
    }

    static func make(
        for report: ImageCompressionReport,
        locale: Locale = .current
    ) -> CommandAlertContent? {
        let permissionFailures = report.failures.filter {
            $0.kind == .permissionDenied || $0.kind == .readOnlyFileSystem
        }
        let unreadableImages = permissionFailures.compactMap { failure -> URL? in
            guard case .source = failure else { return nil }
            return failure.sourceURL
        }
        let imagesWithUnwritableFolders = permissionFailures.compactMap { failure -> URL? in
            guard case .destination = failure else { return nil }
            return failure.sourceURL
        }
        let fileDateIssues = report.outputs.filter { $0.fileDateError != nil }

        var lines: [String] = []
        for (access, images) in [
            (AccessFailure.read, unreadableImages),
            (AccessFailure.write, imagesWithUnwritableFolders),
        ] where !images.isEmpty {
            lines.append(compressionPermissionBody(
                access: access,
                scope: report.outputURLs.isEmpty ? .all : .partial,
                subject: CommandAlertText.subject(for: images),
                locale: locale
            ))
        }

        if !fileDateIssues.isEmpty {
            let subject = CommandAlertText.subject(
                for: fileDateIssues.map(\.url)
            )
            let scope: IssueScope = fileDateIssues.count < report.items.count
                ? .partial
                : .all
            lines.append(
                fileDateBody(
                    scope: scope,
                    subject: subject,
                    locale: locale
                )
            )
        }

        guard !lines.isEmpty else {
            return nil
        }
        return CommandAlertContent(
            body: lines.joined(separator: "\n"),
            locale: locale
        )
    }

    /// 读取与目录写入权限分别汇总，每种语义使用完整本地化句式。
    private static func compressionPermissionBody(
        access: AccessFailure,
        scope: IssueScope,
        subject: CommandAlertSubject,
        locale: Locale
    ) -> String {
        let resource: LocalizedStringResource
        switch (access, scope, subject) {
        case (.read, .all, .named(let name)):
            resource = LocalizedStringResource(
                "alert.imageCompression.readPermission.all.named",
                defaultValue: "Couldn’t compress “\(name)” because it can’t be read.",
                locale: locale,
                comment: "The named image could not be compressed because it cannot be read"
            )
        case (.read, .all, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.imageCompression.readPermission.all.counted",
                defaultValue: "Couldn’t compress the selected images because \(count) images can’t be read.",
                locale: locale,
                comment: "No selected images could be compressed; the argument counts unreadable images"
            )
        case (.read, .partial, .named(let name)):
            resource = LocalizedStringResource(
                "alert.imageCompression.readPermission.partial.named",
                defaultValue: "Some images couldn’t be compressed because “\(name)” can’t be read.",
                locale: locale,
                comment: "Other images were compressed, but the named image cannot be read"
            )
        case (.read, .partial, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.imageCompression.readPermission.partial.counted",
                defaultValue: "Some images couldn’t be compressed because \(count) images can’t be read.",
                locale: locale,
                comment: "Other images were compressed; the argument counts unreadable images"
            )
        case (.write, .all, .named(let name)):
            resource = LocalizedStringResource(
                "alert.imageCompression.writePermission.all.named",
                defaultValue: "Couldn’t compress “\(name)” because its folder isn’t writable.",
                locale: locale,
                comment: "The named image could not be compressed because its containing folder is not writable"
            )
        case (.write, .all, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.imageCompression.writePermission.all.counted",
                defaultValue: "Couldn’t compress the selected images because the folders containing \(count) images aren’t writable.",
                locale: locale,
                comment: "No selected images could be compressed; the argument counts images whose containing folders are not writable"
            )
        case (.write, .partial, .named(let name)):
            resource = LocalizedStringResource(
                "alert.imageCompression.writePermission.partial.named",
                defaultValue: "Some images couldn’t be compressed because the folder containing “\(name)” isn’t writable.",
                locale: locale,
                comment: "Other images were compressed, but the folder containing the named image is not writable"
            )
        case (.write, .partial, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.imageCompression.writePermission.partial.counted",
                defaultValue: "Some images couldn’t be compressed because the folders containing \(count) images aren’t writable.",
                locale: locale,
                comment: "Other images were compressed; the argument counts images whose containing folders are not writable"
            )
        }
        return String(localized: resource)
    }

    /// 已写出 JPG 的时间属性问题按完整句式覆盖全部/部分和名称/数量。
    private static func fileDateBody(
        scope: IssueScope,
        subject: CommandAlertSubject,
        locale: Locale
    ) -> String {
        let resource: LocalizedStringResource
        switch (scope, subject) {
        case (.all, .named(let name)):
            resource = LocalizedStringResource(
                "alert.imageCompression.fileDates.all.named",
                defaultValue: "“\(name)” was compressed, but its date attributes couldn’t be updated.",
                locale: locale,
                comment: "The named image was compressed, but its creation and modification dates could not be updated"
            )
        case (.all, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.imageCompression.fileDates.all.counted",
                defaultValue: "The images were compressed, but the date attributes of \(count) images couldn’t be updated.",
                locale: locale,
                comment: "All processed images have date-attribute problems; the argument is the affected image count"
            )
        case (.partial, .named(let name)):
            resource = LocalizedStringResource(
                "alert.imageCompression.fileDates.partial.named",
                defaultValue: "Some images were compressed, but the date attributes of “\(name)” couldn’t be updated.",
                locale: locale,
                comment: "Other images completed normally, but the named compressed image has a date-attribute problem"
            )
        case (.partial, .counted(let count)):
            resource = LocalizedStringResource(
                "alert.imageCompression.fileDates.partial.counted",
                defaultValue: "Some images were compressed, but the date attributes of \(count) images couldn’t be updated.",
                locale: locale,
                comment: "Other images completed normally; the argument is the number of compressed images with date-attribute problems"
            )
        }
        return String(localized: resource)
    }
}

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

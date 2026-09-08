import AppKit
import Foundation
import OSLog

/// 文件创建完成后交给 Finder 反馈的不可变结果。
nonisolated struct CreateNewFileSuccess: Equatable, Sendable {
    let fileURL: URL
    let elapsedMilliseconds: UInt64
}

/// 模板读取与目标写入拥有不同的失败对象，不能混用权限文案。
nonisolated enum CreateNewFileFailure: Error, Equatable, Sendable {
    case template(FileTemplateID, SystemErrorSnapshot)
    case destination(directoryURL: URL, systemError: SystemErrorSnapshot)

    var systemError: SystemErrorSnapshot {
        switch self {
        case .template(_, let error), .destination(_, let error): error
        }
    }
}

typealias CreateNewFileOutcome = Result<CreateNewFileSuccess, CreateNewFileFailure>

/// 通过稳定模板身份取得内容，再排他创建一个输出文件。
@MainActor
struct CreateNewFileHandler: ContextCommandHandling {
    private let library: FileTemplateLibrary

    nonisolated init(library: FileTemplateLibrary) {
        self.library = library
    }

    @concurrent nonisolated func execute(
        _ command: CreateNewFileCommand
    ) async -> CreateNewFileOutcome {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let content: FileTemplateContent
        do {
            content = try await library.content(for: command.templateID)
        } catch {
            return .failure(.template(
                command.templateID,
                SystemErrorSnapshot(capturing: error)
            ))
        }

        do {
            let fileURL = try Self.createFile(from: content, in: command.directoryPath)
            return .success(CreateNewFileSuccess(
                fileURL: fileURL,
                elapsedMilliseconds: (DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            ))
        } catch {
            return .failure(.destination(
                directoryURL: command.directoryPath.url,
                systemError: SystemErrorSnapshot(capturing: error)
            ))
        }
    }

    /// 内容已在模板库串行边界内取得；随后删除或编辑配置不改变这次创建事实。
    nonisolated static func createFile(
        from content: FileTemplateContent,
        in directoryPath: AbsoluteFilePath
    ) throws -> URL {
        let directoryURL = directoryPath.url
        // 直接写入保留路径失效与权限拒绝的实际错误，不以存在性查询折叠失败原因。
        let preferredURL = directoryURL.appendingPathComponent(content.template.defaultFileName)
        for candidate in FileCollisionNaming.candidateURLs(for: preferredURL) {
            do {
                try content.data.write(to: candidate, options: .withoutOverwriting)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    func present(_ outcome: CreateNewFileOutcome, requestID: UUID) {
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

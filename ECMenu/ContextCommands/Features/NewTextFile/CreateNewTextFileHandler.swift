import AppKit
import Foundation
import OSLog

// MARK: - ==================== 类型化计划与结果 ====================

/// 描述一次成功创建产生的事实，供反馈阶段使用。
struct CreateNewTextFileSuccess: Equatable, Sendable {
    /// 已经创建且需要在 Finder 中选中的文件。
    let fileURL: URL

    /// 从命令开始执行到文件创建完成的耗时，用于诊断性能。
    let elapsedMilliseconds: UInt64
}

/// 新建 TXT 没有完成时保留的唯一系统事实。
struct CreateNewTextFileFailure: Error, Equatable, Sendable {
    /// 命令尝试写入的目标目录。
    let directoryURL: URL

    /// 文件系统边界捕获的底层错误快照。
    let systemError: SystemErrorSnapshot

    /// 从底层错误推导出的反馈和日志类别。
    var kind: FileSystemErrorKind {
        FileSystemErrorKind(classifying: systemError)
    }
}

/// 新建 TXT 执行阶段返回的类型化成功或失败。
typealias CreateNewTextFileOutcome = Result<
    CreateNewTextFileSuccess,
    CreateNewTextFileFailure
>

/// 在主应用中规划、执行并反馈一次新建 TXT 命令。
@MainActor
struct CreateNewTextFileHandler: ContextCommandHandling {
    // MARK: - ==================== 执行管线编排 ====================

    /// 在后台执行器读取系统事实、构造计划并执行文件创建。
    /// - Parameter command: Extension 采集 Finder 快照后构造的命令。
    /// - Returns: 不直接反馈 UI 的类型化执行结果。
    @concurrent nonisolated func execute(
        _ command: CreateNewTextFileCommand
    ) async -> CreateNewTextFileOutcome {
        let startedAt = DispatchTime.now().uptimeNanoseconds

        return Self.execute(
            in: command.directoryPath,
            startedAt: startedAt
        )
    }

    // MARK: - ==================== 纯函数：构造候选路径 ====================

    /// 根据业务命名规则构造指定序号的 TXT 候选 URL。
    /// - Parameters:
    ///   - directoryURL: 候选文件所属的目标目录。
    ///   - sequenceNumber: 从 `1` 开始的候选序号；`1` 不附加数字。
    /// - Returns: `untitled.txt`、`untitled_copy.txt` 等确定性候选 URL。
    nonisolated static func candidateFileURL(
        in directoryURL: URL,
        sequenceNumber: Int
    ) -> URL {
        precondition(sequenceNumber >= 1)

        return FileCollisionNaming.candidateURL(
            for: directoryURL.appendingPathComponent("untitled.txt"),
            sequenceNumber: sequenceNumber
        )
    }

    /// 惰性生成目标目录中的全部 TXT 候选 URL，不读取文件系统。
    /// - Parameter directoryURL: 候选文件所属的目标目录。
    /// - Returns: 按业务顺序排列、仅在迭代时计算元素的候选 URL 序列。
    nonisolated static func candidateFileURLs(
        in directoryURL: URL
    ) -> LazyMapSequence<ClosedRange<Int>, URL> {
        return FileCollisionNaming.candidateURLs(
            for: directoryURL.appendingPathComponent("untitled.txt")
        )
    }

    // MARK: - ==================== 副作用：执行计划并映射系统错误 ====================

    /// 重验菜单期已解析的目录，并执行文件创建。
    /// - Parameters:
    ///   - directoryURL: 命令携带的目标目录。
    ///   - startedAt: 整条命令管线的单调时钟起点。
    /// - Returns: 文件创建成功事实或分类后的失败。
    private nonisolated static func execute(
        in directoryPath: AbsoluteFilePath,
        startedAt: UInt64
    ) -> CreateNewTextFileOutcome {
        let directoryURL = directoryPath.url
        do {
            let createdURL = try createEmptyTextFile(
                in: directoryPath
            )
            let elapsedMilliseconds = (
                DispatchTime.now().uptimeNanoseconds - startedAt
            ) / 1_000_000
            return .success(
                CreateNewTextFileSuccess(
                    fileURL: createdURL,
                    elapsedMilliseconds: elapsedMilliseconds
                )
            )
        } catch {
            return .failure(
                CreateNewTextFileFailure(
                    directoryURL: directoryURL,
                    systemError: SystemErrorSnapshot(capturing: error)
                )
            )
        }
    }

    /// 按纯命名规则逐个排他创建，不先查询候选是否存在。
    /// - Parameter directoryPath: 已解析的绝对目标目录路径。
    /// - Returns: 实际创建的文件 URL。
    /// - Throws: 目标无效、不可写或底层写入失败时抛出系统错误。
    nonisolated static func createEmptyTextFile(
        in directoryPath: AbsoluteFilePath
    ) throws -> URL {
        let directoryURL = directoryPath.url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        for fileURL in candidateFileURLs(in: directoryURL) {
            do {
                try Data().write(to: fileURL, options: .withoutOverwriting)
                return fileURL
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }

        throw CocoaError(.fileWriteFileExists)
    }

    // MARK: - ==================== 副作用：呈现执行结果 ====================

    /// 在唯一反馈出口把执行结果转换为 Finder 选择、日志、提示音或弹窗。
    /// - Parameters:
    ///   - outcome: `execute` 返回的类型化结果。
    ///   - requestID: 用于关联主应用任务和本地诊断日志的标识符。
    func present(
        _ outcome: CreateNewTextFileOutcome,
        requestID: UUID
    ) {
        switch outcome {
        case .success(let success):
            let didSelectInMainViewer = NSWorkspace.shared.selectFile(
                success.fileURL.path,
                inFileViewerRootedAtPath: ""
            )
            if !didSelectInMainViewer {
                CreateNewTextFileOutcomeLogger.logSelectionFailure(
                    success,
                    requestID: requestID
                )
            }
            CreateNewTextFileOutcomeLogger.logSuccess(
                success,
                requestID: requestID
            )

        case .failure(let failure):
            CreateNewTextFileOutcomeLogger.logFailure(
                failure,
                requestID: requestID
            )
            if let content = CreateNewTextFileAlertContent.make(for: failure) {
                CommandAlertPresenter.present(content)
            } else {
                NSSound.beep()
            }
        }
    }
}

// MARK: - ==================== 纯函数：构造错误提示内容 ====================

/// 只把用户可处理的文件系统失败转换为统一文案。
nonisolated enum CreateNewTextFileAlertContent {
    static func make(
        for failure: CreateNewTextFileFailure,
        locale: Locale = .current
    ) -> CommandAlertContent? {
        switch failure.kind {
        case .permissionDenied, .readOnlyFileSystem:
            break
        case .unavailable, .other:
            return nil
        }

        let subject = CommandAlertText.subject(for: [failure.directoryURL])
        guard case .named(let directoryName) = subject else {
            preconditionFailure("A new text file has exactly one destination directory")
        }
        let body = String(
            localized: LocalizedStringResource(
                "alert.newTextFile.writePermission.named",
                defaultValue: "Couldn’t create a TXT file because “\(directoryName)” isn’t writable.",
                locale: locale,
                comment: "A TXT file could not be created in the named directory because it is not writable"
            )
        )
        return CommandAlertContent(
            body: body,
            locale: locale
        )
    }
}

// MARK: - ==================== 副作用：记录诊断 ====================

/// 只记录新建 TXT 的详细执行事实，不构造或显示弹窗。
@MainActor
private enum CreateNewTextFileOutcomeLogger {
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "NewTextFile"
    )

    static func logSuccess(
        _ success: CreateNewTextFileSuccess,
        requestID: UUID
    ) {
        logger.info(
            "Created a TXT file for request \(requestID.uuidString, privacy: .public) in \(success.elapsedMilliseconds) ms at \(success.fileURL.path, privacy: .private)"
        )
    }

    static func logSelectionFailure(
        _ success: CreateNewTextFileSuccess,
        requestID: UUID
    ) {
        logger.error(
            "Finder could not select the TXT file for request \(requestID.uuidString, privacy: .public) at \(success.fileURL.path, privacy: .private)"
        )
    }

    static func logFailure(
        _ failure: CreateNewTextFileFailure,
        requestID: UUID
    ) {
        let summary: String
        switch failure.kind {
        case .unavailable:
            summary = "Target directory became unavailable"
        case .permissionDenied:
            summary = "Permission denied"
        case .readOnlyFileSystem:
            summary = "Read-only file system"
        case .other:
            summary = "File-system failure"
        }
        logFileSystemFailure(
            summary,
            directoryURL: failure.directoryURL,
            error: failure.systemError,
            requestID: requestID
        )
    }

    private static func logFileSystemFailure(
        _ summary: String,
        directoryURL: URL,
        error: SystemErrorSnapshot,
        requestID: UUID
    ) {
        logger.error(
            "\(summary, privacy: .public) for create-new-text-file request \(requestID.uuidString, privacy: .public) at \(directoryURL.path, privacy: .private) [\(error.domain, privacy: .public):\(error.code, privacy: .public)]: \(error.localizedDescription, privacy: .private)"
        )
    }
}

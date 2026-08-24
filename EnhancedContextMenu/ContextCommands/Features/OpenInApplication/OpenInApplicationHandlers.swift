import AppKit
import Foundation
import OSLog

// MARK: - ==================== 类型化计划与结果 ====================

/// 描述一次通过固定外部应用打开 Finder 目标的不可变计划。
nonisolated struct OpenInApplicationPlan: Equatable, Sendable {
    /// 用户在 Finder 中指向的原始路径；符号链接不替换为最终目标。
    let targetURL: URL

    /// Launch Services 定位到的外部应用 bundle URL。
    let applicationURL: URL

    /// 用于诊断和用户反馈的外部应用声明。
    let application: ContextCommandApplicationRequirement
}

/// 执行期读取到的目标状态，不允许表达“不存在但同时是目录”。
nonisolated enum OpenInApplicationTargetState: Equatable, Sendable {
    /// 路径已经消失或断开的符号链接无法到达目标。
    case unavailable

    /// 路径当前指向普通文件。
    case file

    /// 路径当前指向目录；package 也属于此状态。
    case directory

    /// 判断执行期状态是否满足命令声明的目标种类。
    func satisfies(_ targetKind: OpenInApplicationTargetKind) -> Bool {
        switch (self, targetKind) {
        case (.file, .item), (.directory, .item), (.directory, .directory):
            return true
        case (.unavailable, _), (.file, .directory):
            return false
        }
    }
}

/// 外部应用打开命令需要反馈的稳定失败类型。
nonisolated enum OpenInApplicationFailure: Error, Equatable, Sendable {
    /// 命令目标在执行时已经消失或不再符合种类约束。
    case targetUnavailable

    /// Launch Services 无法定位命令声明的固定应用。
    case applicationUnavailable(ContextCommandApplicationRequirement)

    /// 系统已经接受计划，但外部应用启动或打开目标失败。
    case launchFailed(
        OpenInApplicationPlan,
        SystemErrorSnapshot
    )
}

/// 外部应用打开命令从规划到系统回调的最终事实。
nonisolated enum OpenInApplicationOutcome: Equatable, Sendable {
    /// 系统已经成功把目标交给外部应用。
    case succeeded(OpenInApplicationPlan)

    /// 目标、应用或启动操作不可用。
    case failed(OpenInApplicationFailure)
}

// MARK: - ==================== 类型化命令 Handler ====================

/// 由具体命令类型提供固定应用和目标约束的共享 Handler。
@MainActor
struct OpenInApplicationHandler<Command: OpenInApplicationCommand>:
    ContextCommandHandling
{
    /// 执行命令类型完整声明的单目标外部应用管线。
    @concurrent nonisolated func execute(
        _ command: Command
    ) async -> OpenInApplicationOutcome {
        await OpenInApplicationExecution.execute(command)
    }

    /// 使用同一命令声明的产品名称呈现结果。
    func present(_ outcome: OpenInApplicationOutcome, requestID: UUID) {
        OpenInApplicationFeedback.present(
            outcome,
            commandTitle: Command.descriptor.title,
            requestID: requestID
        )
    }
}

typealias OpenInVSCodeHandler = OpenInApplicationHandler<OpenInVSCodeCommand>
typealias OpenInITerm2Handler = OpenInApplicationHandler<OpenInITerm2Command>

// MARK: - ==================== 执行管线：副作用 - 纯函数 - 副作用 ====================

/// 组合文件系统事实、纯计划、Launch Services 定位和外部应用启动。
nonisolated enum OpenInApplicationExecution {
    /// 执行一个由共享 Command 完整声明的外部应用打开命令。
    static func execute<Command: OpenInApplicationCommand>(
        _ command: Command
    ) async -> OpenInApplicationOutcome {
        let facts = readTargetFacts(for: command.targetPath)
        let application = Command.applicationRequirement
        let applicationURL = await MainActor.run {
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: application.bundleIdentifier
            )
        }

        switch makePlan(
            for: command,
            targetState: facts,
            applicationURL: applicationURL
        ) {
        case .success(let plan):
            return await launch(plan)
        case .failure(let failure):
            return .failed(failure)
        }
    }

    // MARK: - ==================== 副作用：读取系统事实 ====================

    /// 读取候选路径跟随符号链接后的存在性和目录类型。
    private static func readTargetFacts(
        for path: AbsoluteFilePath
    ) -> OpenInApplicationTargetState {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: path.path,
            isDirectory: &isDirectory
        ) else {
            return .unavailable
        }
        return isDirectory.boolValue ? .directory : .file
    }

    // MARK: - ==================== 纯函数：构造执行计划 ====================

    /// 重验命令目标和外部应用，构造唯一执行计划。
    static func makePlan<Command: OpenInApplicationCommand>(
        for command: Command,
        targetState: OpenInApplicationTargetState,
        applicationURL: URL?
    ) -> Result<OpenInApplicationPlan, OpenInApplicationFailure> {
        guard targetState.satisfies(Command.targetKind) else {
            return .failure(.targetUnavailable)
        }
        let application = Command.applicationRequirement
        guard let applicationURL else {
            return .failure(.applicationUnavailable(application))
        }
        return .success(
            OpenInApplicationPlan(
                targetURL: command.targetPath.url,
                applicationURL: applicationURL.standardizedFileURL,
                application: application
            )
        )
    }

    // MARK: - ==================== 副作用：交给外部应用 ====================

    /// 使用 Launch Services 打开单一目标，并等待异步系统回调。
    @MainActor
    private static func launch(
        _ plan: OpenInApplicationPlan
    ) async -> OpenInApplicationOutcome {
        await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [plan.targetURL],
                withApplicationAt: plan.applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(
                        returning: .failed(
                            .launchFailed(
                                plan,
                                SystemErrorSnapshot(capturing: error)
                            )
                        )
                    )
                } else {
                    continuation.resume(returning: .succeeded(plan))
                }
            }
        }
    }
}

// MARK: - ==================== 纯函数：构造错误提示内容 ====================

/// 外部应用失败只保留稳定的命令级说明。
nonisolated enum OpenInApplicationAlertContent {
    static func make(
        for outcome: OpenInApplicationOutcome,
        commandTitle: String
    ) -> CommandAlertContent? {
        guard case .failed = outcome else {
            return nil
        }
        return CommandAlertContent(body: "无法\(commandTitle)。")
    }
}

// MARK: - ==================== 副作用：日志与用户反馈 ====================

/// 把外部应用打开结果编排为一次日志记录和一次错误反馈。
@MainActor
private enum OpenInApplicationFeedback {
    static func present(
        _ outcome: OpenInApplicationOutcome,
        commandTitle: String,
        requestID: UUID
    ) {
        OpenInApplicationOutcomeLogger.log(outcome, requestID: requestID)
        if let content = OpenInApplicationAlertContent.make(
            for: outcome,
            commandTitle: commandTitle
        ) {
            CommandAlertPresenter.present(content)
        }
    }
}

/// 只记录外部应用打开的详细结果，不构造或显示弹窗。
@MainActor
private enum OpenInApplicationOutcomeLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EnhancedContextMenu",
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

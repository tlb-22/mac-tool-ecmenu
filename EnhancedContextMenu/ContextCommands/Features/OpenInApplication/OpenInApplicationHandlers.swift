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

/// 外部应用打开命令需要反馈的稳定失败类型。
nonisolated enum OpenInApplicationFailure: Error, Equatable, Sendable {
    /// Finder 快照不是一个仍然有效的单一目标。
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

// MARK: - ==================== 具体命令 Handler ====================

/// 在主应用中通过 Visual Studio Code 打开一个 Finder 目标。
@MainActor
struct OpenInVSCodeHandler: ContextCommandHandling {
    /// 执行单目标 VS Code 管线，并允许文件或目录。
    @concurrent nonisolated func execute(
        _ command: OpenInVSCodeCommand
    ) async -> OpenInApplicationOutcome {
        await OpenInApplicationExecution.execute(
            snapshot: command.finderContext,
            descriptor: OpenInVSCodeCommand.descriptor,
            requiresDirectory: false
        )
    }

    /// 在主线程统一反馈 VS Code 打开结果。
    func present(_ outcome: OpenInApplicationOutcome, requestID: UUID) {
        OpenInApplicationFeedback.present(
            outcome,
            commandTitle: OpenInVSCodeCommand.descriptor.title,
            requestID: requestID
        )
    }
}

/// 在主应用中让 iTerm2 进入一个 Finder 目录目标。
@MainActor
struct OpenInITerm2Handler: ContextCommandHandling {
    /// 执行单目标 iTerm2 管线，并要求最终目标是目录。
    @concurrent nonisolated func execute(
        _ command: OpenInITerm2Command
    ) async -> OpenInApplicationOutcome {
        await OpenInApplicationExecution.execute(
            snapshot: command.finderContext,
            descriptor: OpenInITerm2Command.descriptor,
            requiresDirectory: true
        )
    }

    /// 在主线程统一反馈 iTerm2 打开结果。
    func present(_ outcome: OpenInApplicationOutcome, requestID: UUID) {
        OpenInApplicationFeedback.present(
            outcome,
            commandTitle: OpenInITerm2Command.descriptor.title,
            requestID: requestID
        )
    }
}

// MARK: - ==================== 执行管线：副作用 - 纯函数 - 副作用 ====================

/// 组合文件系统事实、纯计划、Launch Services 定位和外部应用启动。
nonisolated enum OpenInApplicationExecution {
    /// 执行一个由共享 Command 完整声明的外部应用打开命令。
    static func execute(
        snapshot: FinderContextSnapshot,
        descriptor: ContextCommandDescriptor,
        requiresDirectory: Bool
    ) async -> OpenInApplicationOutcome {
        let facts = readTargetFacts(for: snapshot)

        guard let application = descriptor.requiredApplication else {
            preconditionFailure("An external-application command must declare its application")
        }
        let applicationURL = await MainActor.run {
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: application.bundleIdentifier
            )
        }

        switch makePlan(
            for: snapshot,
            existingURLs: facts.existingURLs,
            directoryURLs: facts.directoryURLs,
            application: application,
            applicationURL: applicationURL,
            requiresDirectory: requiresDirectory
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
        for snapshot: FinderContextSnapshot
    ) -> (existingURLs: Set<URL>, directoryURLs: Set<URL>) {
        var existingURLs: Set<URL> = []
        var directoryURLs: Set<URL> = []

        for url in snapshot.urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ) else {
                continue
            }
            let normalizedURL = url.standardizedFileURL
            existingURLs.insert(normalizedURL)
            if isDirectory.boolValue {
                directoryURLs.insert(normalizedURL)
            }
        }
        return (existingURLs, directoryURLs)
    }

    // MARK: - ==================== 纯函数：构造执行计划 ====================

    /// 根据 Finder 快照、文件系统事实和应用位置构造唯一执行计划。
    static func makePlan(
        for snapshot: FinderContextSnapshot,
        existingURLs: Set<URL>,
        directoryURLs: Set<URL>,
        application: ContextCommandApplicationRequirement,
        applicationURL: URL?,
        requiresDirectory: Bool
    ) -> Result<OpenInApplicationPlan, OpenInApplicationFailure> {
        guard let targetURL = OpenInApplicationTargetResolver.targetURL(
            for: snapshot,
            existingURLs: existingURLs,
            directoryURLs: directoryURLs,
            requiresDirectory: requiresDirectory
        ) else {
            return .failure(.targetUnavailable)
        }
        guard let applicationURL else {
            return .failure(.applicationUnavailable(application))
        }
        return .success(
            OpenInApplicationPlan(
                targetURL: targetURL,
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

import AppKit
import Darwin
import Foundation
import OSLog

// MARK: - ==================== 类型化计划与结果 ====================

/// 描述一次剪贴板写入所需的、已经解析完成的不可变计划。
nonisolated struct CopyPathPlan: Equatable, Sendable {
    /// 按 Finder 提供顺序排列的绝对文件 URL。
    let itemURLs: [URL]

    /// 每个绝对 POSIX 路径占一行的剪贴板正文。
    var pasteboardString: String {
        itemURLs.map(\.path).joined(separator: "\n")
    }
}

/// 拷贝路径用例中需要反馈的失败类型。
nonisolated enum CopyPathFailure: Error, Sendable {
    /// Finder 快照无法确定至少一个有效目标；记录日志并播放错误提示音。
    case targetUnavailable
}

/// 拷贝路径规划阶段返回的类型化成功或失败。
typealias CopyPathOutcome = Result<CopyPathPlan, CopyPathFailure>

/// 在主应用中解析路径并写入系统通用剪贴板。
@MainActor
struct CopyPathHandler: ContextCommandHandling {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EnhancedContextMenu",
        category: "CopyPath"
    )

    // MARK: - ==================== 执行管线编排 ====================

    /// 在通用执行器读取路径存在性，并用纯函数构造剪贴板计划。
    @concurrent nonisolated func execute(
        _ command: CopyPathCommand
    ) async -> CopyPathOutcome {
        let snapshot = command.finderContext
        let existingURLs = Self.readExistingURLs(for: snapshot)
        return Self.makePlan(
            for: snapshot,
            existingURLs: existingURLs
        )
    }

    // MARK: - ==================== 副作用：读取文件系统事实 ====================

    /// 读取快照候选项当前是否仍然存在。
    private nonisolated static func readExistingURLs(
        for snapshot: FinderContextSnapshot
    ) -> Set<URL> {
        return Set(
            snapshot.urls
                .filter(fileSystemItemExists)
                .map(\.standardizedFileURL)
        )
    }

    /// 使用 `lstat` 判断路径对象本身是否存在，不跟随符号链接目标。
    private nonisolated static func fileSystemItemExists(_ url: URL) -> Bool {
        var information = stat()
        return lstat(url.path, &information) == 0
    }

    // MARK: - ==================== 纯函数：构造剪贴板计划 ====================

    /// 根据 Finder 快照和边界事实选择有序路径集合。
    nonisolated static func makePlan(
        for snapshot: FinderContextSnapshot,
        existingURLs: Set<URL>
    ) -> CopyPathOutcome {
        let normalizedExistingURLs = Set(
            existingURLs.map(\.standardizedFileURL)
        )
        let candidates: [URL]

        switch snapshot {
        case .container(let path), .sidebar(let path):
            candidates = [URL(fileURLWithPath: path)]
        case .items(let selection):
            candidates = selection.urls
        }

        let itemURLs = candidates
            .map(\.standardizedFileURL)
            .filter { normalizedExistingURLs.contains($0) }
        guard !itemURLs.isEmpty, itemURLs.count == candidates.count else {
            return .failure(.targetUnavailable)
        }
        return .success(CopyPathPlan(itemURLs: itemURLs))
    }

    // MARK: - ==================== 副作用：写入剪贴板并反馈 ====================

    /// 在主线程唯一出口写入剪贴板，失败时记录日志并播放提示音。
    func present(_ outcome: CopyPathOutcome, requestID: UUID) {
        switch outcome {
        case .success(let plan):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(plan.pasteboardString, forType: .string) else {
                logger.error(
                    "Could not write copy-path request \(requestID.uuidString, privacy: .public) to the pasteboard"
                )
                NSSound.beep()
                return
            }
            logger.info(
                "Copied \(plan.itemURLs.count) paths for request \(requestID.uuidString, privacy: .public)"
            )

        case .failure(.targetUnavailable):
            logger.error(
                "Could not resolve paths for copy-path request \(requestID.uuidString, privacy: .public)"
            )
            NSSound.beep()
        }
    }
}

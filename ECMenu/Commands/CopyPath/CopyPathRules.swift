/**
 定义复制路径的计划、成功与失败结果，并从路径事实生成剪贴板文本。
 以纯规则处理选择内容和有效目标，系统查询与写入由外部边界执行。
 */

import Foundation

/// 已经重验的有序路径及其剪贴板正文。
nonisolated struct CopyPathPlan: Equatable, Sendable {
    let itemURLs: [URL]
    var pasteboardString: String { itemURLs.map(\.path).joined(separator: "\n") }
}

nonisolated enum CopyPathFailure: Error, Equatable, Sendable {
    case targetUnavailable
    case pasteboardWriteFailed
}

/// 仅在剪贴板接受完整正文后产生。
nonisolated struct CopyPathSuccess: Equatable, Sendable {
    let itemCount: Int
}

nonisolated enum CopyPathOutcome: Equatable, Sendable {
    case success(CopyPathSuccess)
    case failure(CopyPathFailure)
    case cancelled
}

nonisolated enum CopyPathRules {
    static func makePlan(
        for command: CopyPathCommand,
        existingURLs: Set<URL>
    ) -> Result<CopyPathPlan, CopyPathFailure> {
        let existing = Set(existingURLs.map(\.standardizedFileURL))
        let candidates = command.paths.map(\.url)
        guard candidates.allSatisfy({ existing.contains($0) }) else {
            return .failure(.targetUnavailable)
        }
        return .success(CopyPathPlan(itemURLs: candidates))
    }
}

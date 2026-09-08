/**
 按可见性计划逐项设置文件隐藏属性并汇总结果。
 在项目之间响应任务取消，保留已经成功的操作并收集系统失败。
 */

import Foundation

nonisolated struct VisibilityPlatform: Sendable {
    let setHidden: @Sendable (URL, Bool) throws -> Void
}

/// 组合 Finder 目标解析、计划构造和逐项隐藏属性写入。
nonisolated enum VisibilityExecution {
    /// 顺序执行完整可见性操作；调用方负责执行隔离。
    static func execute(
        selection: FinderItemSelection,
        operation: VisibilityOperation,
        platform: VisibilityPlatform
    ) -> VisibilityReport {
        let plan = VisibilityRules.makePlan(
            operation: operation,
            itemURLs: selection.urls
        )
        return execute(plan, platform: platform)
    }

    // MARK: - ==================== 副作用：执行计划并分类错误 ====================

    /// 逐项设置隐藏属性，保留全部成功并收集失败。
    static func execute(_ plan: VisibilityPlan, platform: VisibilityPlatform) -> VisibilityReport {
        var succeededCount = 0
        var issues: [VisibilityIssue] = []

        for itemURL in plan.itemURLs {
            guard !Task.isCancelled else {
                break
            }

            do {
                try platform.setHidden(itemURL, plan.operation.isHidden)
                succeededCount += 1
            } catch {
                issues.append(issue(for: error, itemURL: itemURL))
            }
        }

        return VisibilityReport(
            succeededCount: succeededCount,
            issues: issues
        )
    }

    /// 将系统错误映射为决定批量反馈策略的稳定问题。
    static func issue(for error: Error, itemURL: URL) -> VisibilityIssue {
        let systemError = SystemErrorSnapshot(capturing: error)
        return VisibilityIssue(
            itemURL: itemURL,
            systemError: systemError
        )
    }
}

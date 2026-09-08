/**
 定义显示隐藏操作、目标计划和批次执行报告。
 将操作方向与目标选择转换为纯数据，保留逐项失败供反馈使用。
 */

import Foundation

/// 隐藏属性需要达到的最终状态。
nonisolated enum VisibilityOperation: String, Equatable, Sendable {
    /// 设置 macOS 文件隐藏属性。
    case hide

    /// 清除 macOS 文件隐藏属性。
    case show

    /// 写入 `URLResourceValues.isHidden` 的最终值。
    var isHidden: Bool { self == .hide }
}

/// 描述一次隐藏属性写入所需的不可变执行计划。
nonisolated struct VisibilityPlan: Equatable, Sendable {
    /// 本次命令要求达到的最终隐藏状态。
    let operation: VisibilityOperation

    /// 不包含点号名称、保持 Finder 选择顺序的对象。
    let itemURLs: [URL]
}

/// 一项没有完成的隐藏属性操作。
nonisolated struct VisibilityIssue: Equatable, Sendable {
    /// 没有完成属性写入的对象。
    let itemURL: URL

    /// 底层系统错误的稳定快照。
    let systemError: SystemErrorSnapshot

    /// 从唯一底层错误事实推导出的反馈类别。
    var kind: FileSystemErrorKind {
        FileSystemErrorKind(classifying: systemError)
    }
}

/// 批量隐藏或显示结束后的完整事实。
nonisolated struct VisibilityReport: Equatable, Sendable {
    /// 成功达到目标状态的普通名称对象数量。
    let succeededCount: Int

    /// 所有失败项目；成功项目不回滚。
    let issues: [VisibilityIssue]
}

nonisolated enum VisibilityRules {
    /// 过滤不能通过隐藏属性显示的点号名称，并形成最终执行计划。
    static func makePlan(
        operation: VisibilityOperation,
        itemURLs: [URL]
    ) -> VisibilityPlan {
        return VisibilityPlan(
            operation: operation,
            itemURLs: itemURLs.filter { !isDotItem($0) }
        )
    }

    /// 判断对象是否由点号名称天然决定为隐藏。
    static func isDotItem(_ itemURL: URL) -> Bool {
        itemURL.lastPathComponent.hasPrefix(".")
    }
}

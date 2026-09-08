/**
 根据目标状态与应用可用性生成打开计划，或返回明确失败。
 定义输入事实、计划和结果类型，使文件与应用选择规则保持纯计算。
 */

import Foundation

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

nonisolated enum OpenInApplicationRules {
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
}

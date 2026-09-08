/**
 读取目标和应用安装事实，经领域规则生成打开计划后发起启动。
 通过窄平台边界衔接文件检查、应用查找与主执行器上的系统启动。
 */

import Foundation

nonisolated struct OpenInApplicationPlatform: Sendable {
    let targetState: @Sendable (AbsoluteFilePath) -> OpenInApplicationTargetState
    let applicationURL: @MainActor @Sendable (ContextCommandApplicationRequirement) -> URL?
    let launch: @MainActor @Sendable (OpenInApplicationPlan) async -> OpenInApplicationOutcome
}

nonisolated enum OpenInApplicationExecution {
    static func execute<Command: OpenInApplicationCommand>(
        _ command: Command,
        platform: OpenInApplicationPlatform
    ) async -> OpenInApplicationOutcome {
        let facts = platform.targetState(command.targetPath)
        let applicationURL = await platform.applicationURL(Command.applicationRequirement)
        switch OpenInApplicationRules.makePlan(
            for: command,
            targetState: facts,
            applicationURL: applicationURL
        ) {
        case .success(let plan): return await platform.launch(plan)
        case .failure(let failure): return .failed(failure)
        }
    }
}

/**
 实现打开命令所需的目标检查、Launch Services 应用查找与 NSWorkspace 启动。
 把系统调用结果转换为业务定义的目标状态和执行结果。
 */

import AppKit
import Foundation

extension OpenInApplicationPlatform {
    nonisolated static var system: Self {
        Self(
            targetState: readTargetFacts,
            applicationURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) },
            launch: launch
        )
    }

    /// 读取候选路径跟随符号链接后的存在性和目录类型。
    private nonisolated static func readTargetFacts(
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

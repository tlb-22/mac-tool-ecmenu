/**
 把当前命令菜单配置与模板菜单描述组合成跨进程菜单快照。
 通过模板应用入口读取数据，保持快照组装与实际存储分离。
 */

import Foundation
import OSLog

/// 读取各自所有者的当前事实，投影为可跨进程整体应用的菜单快照。
@MainActor
struct MenuSnapshotProvider {
    let configuration: () -> CommandMenuConfig
    let templates: () async throws -> [FileTemplate]
    private static let logger = Logger(subsystem: ApplicationLogging.subsystem, category: "CommandMenuConfig")

    func currentSnapshot() async -> CommandMenuConfigSnapshot {
        let templateState: FileTemplateMenuState
        do {
            templateState = .available(try await templates().map {
                FileTemplateMenuItem(id: $0.id, displayName: $0.displayName)
            })
        } catch {
            templateState = .unavailable
            Self.logger.error("Could not read file templates for the menu: \(error.localizedDescription, privacy: .private)")
        }
        return CommandMenuConfigSnapshot(configuration: configuration(), fileTemplateState: templateState)
    }
}

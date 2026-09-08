/**
 把 Extension 自身的偏好存储适配为可恢复的命令菜单快照缓存。
 恢复先执行迁移并验证数据，保存只接收副本协调器已应用的完整快照；内存状态仍由协调器持有。
 */

import Foundation
import OSLog

/// Extension 的可恢复快照缓存；不持有另一份菜单内存状态。
struct CommandMenuConfigCacheStore {
    private let defaults: UserDefaults
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "CommandMenuConfig"
    )

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 先执行独立迁移，再恢复有效缓存；迁移或读取失败保留原数据。
    func restore() -> CommandMenuConfigSnapshot? {
        do {
            try CommandMenuConfigCacheMigration.run(in: defaults)
        } catch {
            Self.logger.error("Could not migrate the cached menu configuration: \(error.localizedDescription, privacy: .public)")
        }
        guard let data = defaults.data(forKey: CommandMenuConfigSnapshotCache.key) else {
            return nil
        }
        do {
            return try CommandMenuConfigSnapshotCache.decode(data)
        } catch {
            Self.logger.error("Could not decode the cached menu configuration: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 只有副本已接受的完整响应进入缓存；set 不提供同步落盘回执。
    func store(_ configuration: CommandMenuConfigSnapshot) {
        defaults.set(
            CommandMenuConfigSnapshotCache.encode(configuration),
            forKey: CommandMenuConfigSnapshotCache.key
        )
    }
}

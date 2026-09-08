/**
 执行 Extension 偏好域内的独立缓存升级，将旧开关副本转换为包含模板可用状态的完整快照。
 已有新格式缓存优先；迁移先设置新缓存再删除旧键，模板描述通过后续认证查询取得。
 */

import Foundation

/// 将仅含开关的旧副本一次性迁移为菜单快照；模板描述由主应用后续发布。
enum CommandMenuSettingsCacheMigration {
    static func run(in defaults: UserDefaults) throws {
        guard defaults.object(forKey: CommandMenuSettingsSnapshotCache.key) == nil,
              let data = defaults.data(forKey: CommandMenuSettingsChannel.persistedConfigurationKey)
        else { return }
        let configuration = try CommandMenuSettingsChannel.decodedConfiguration(from: data)
        defaults.set(
            CommandMenuSettingsSnapshotCache.encode(.init(configuration: configuration, fileTemplateState: .unavailable)),
            forKey: CommandMenuSettingsSnapshotCache.key
        )
        defaults.removeObject(forKey: CommandMenuSettingsChannel.persistedConfigurationKey)
    }
}

/**
 定义 Extension 完整菜单副本的稳定缓存键和 JSON 编解码入口。
 缓存与主应用菜单偏好属于各自存储域，有效性由共享快照的 schema 和领域约束共同决定。
 */

import Foundation

/// Extension 的派生缓存格式独立于主应用的菜单开关偏好格式。
nonisolated enum CommandMenuConfigSnapshotCache {
    static let key = "menu-configuration-snapshot-v1"

    static func encode(_ snapshot: CommandMenuConfigSnapshot) -> Data {
        try! JSONEncoder().encode(snapshot)
    }

    static func decode(_ data: Data) throws -> CommandMenuConfigSnapshot {
        try JSONDecoder().decode(CommandMenuConfigSnapshot.self, from: data)
    }
}

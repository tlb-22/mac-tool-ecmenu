/**
 携带已加载的模板清单及缓存、恢复、初始化或迁移的来源。
 为应用层判断本次读取是否需要发布菜单更新提供事实。
 */

import Foundation

/// 读取携带本次发生的存储事实，应用层据此发布初始化和迁移提交。
nonisolated struct FileTemplateLoadResult: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        case cached
        case restored
        case initialized
        case migrated
    }

    let templates: [FileTemplate]
    let origin: Origin
}

/**
 携带已加载的模板清单及缓存、恢复或初始化的来源。
 为应用层判断本次读取是否需要发布菜单更新提供事实。
 */

import Foundation

/// 读取携带本次发生的存储事实，应用层据此发布初始化提交。
nonisolated struct FileTemplateLoadResult: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        case cached
        case restored
        case initialized
    }

    let templates: [FileTemplate]
    let origin: Origin
}

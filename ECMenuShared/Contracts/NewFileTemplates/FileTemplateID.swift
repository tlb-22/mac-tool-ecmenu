/**
 提供模板在存储索引、菜单描述和创建命令之间共用的稳定身份。
 身份使用 UUID 的单值编码，名称编辑或内容副本更换均保持同一个模板引用。
 */

import Foundation

/// 模板在持久化与跨进程命令中的稳定身份，不依赖可编辑名称。
nonisolated struct FileTemplateID: Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

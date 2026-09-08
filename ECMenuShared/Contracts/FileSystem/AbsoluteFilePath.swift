/**
 为跨端文件目标提供经过验证和标准化的绝对路径值，统一 POSIX 路径、文件 URL 与 JSON 表示。
 解码重新建立路径约束，存在性、权限和对象种类属于后续系统事实。
 */

import Foundation

/// 菜单快照和命令负载中已经验证并标准化的绝对文件路径。
nonisolated struct AbsoluteFilePath: Codable, Hashable, Sendable {
    /// 不包含 URL scheme 的标准化 POSIX 路径。
    let path: String

    /// 验证一个原始 POSIX 路径并保存稳定表示。
    init?(path: String) {
        guard !path.isEmpty, path.hasPrefix("/") else {
            return nil
        }
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// 验证一个文件 URL 并保存稳定表示。
    init?(url: URL) {
        guard url.isFileURL else {
            return nil
        }
        self.init(path: url.path)
    }

    /// 恢复 Foundation 文件 URL，不声明路径当前仍然存在。
    var url: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    /// 解码时重新验证绝对路径约束。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let path = try container.decode(String.self)
        guard let value = Self(path: path) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A Finder path must be absolute"
            )
        }
        self = value
    }

    /// 只编码稳定的 POSIX 路径字符串。
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
}

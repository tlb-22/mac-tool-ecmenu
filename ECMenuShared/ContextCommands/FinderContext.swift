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

/// Finder 项目菜单中经过验证的非空选择集合。
nonisolated struct FinderItemSelection: Codable, Equatable, Sendable {
    /// 保持 Finder 原始选择顺序的绝对路径。
    let absolutePaths: [AbsoluteFilePath]

    /// 供编码、日志和系统 API 使用的标准化 POSIX 路径。
    var paths: [String] {
        absolutePaths.map(\.path)
    }

    /// 验证并保存一个非空路径集合。
    /// - Parameter paths: Finder 返回的项目路径，顺序会被完整保留。
    /// - Returns: 输入非空时创建选择值，否则返回 `nil`。
    init?(paths: [String]) {
        guard !paths.isEmpty else {
            return nil
        }
        var absolutePaths: [AbsoluteFilePath] = []
        absolutePaths.reserveCapacity(paths.count)
        for path in paths {
            guard let path = AbsoluteFilePath(path: path) else {
                return nil
            }
            absolutePaths.append(path)
        }
        self.absolutePaths = absolutePaths
    }

    /// 从 Finder URL 验证并保存非空选择集合。
    /// - Parameter urls: Finder 返回的项目 URL。
    /// - Returns: 输入非空时创建选择值，否则返回 `nil`。
    init?(urls: [URL]) {
        guard !urls.isEmpty else {
            return nil
        }
        var absolutePaths: [AbsoluteFilePath] = []
        absolutePaths.reserveCapacity(urls.count)
        for url in urls {
            guard let path = AbsoluteFilePath(url: url) else {
                return nil
            }
            absolutePaths.append(path)
        }
        self.absolutePaths = absolutePaths
    }

    /// 把不可变路径恢复为标准化文件 URL，保持 Finder 选择顺序。
    var urls: [URL] {
        absolutePaths.map(\.url)
    }

    /// 解码时重新验证非空约束，拒绝无法由 Finder 合法产生的项目上下文。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let paths = try container.decode([String].self)
        guard let selection = Self(paths: paths) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A Finder item selection must contain absolute paths"
            )
        }
        self = selection
    }

    /// 只编码路径数组，不暴露内部验证方式。
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(paths)
    }
}

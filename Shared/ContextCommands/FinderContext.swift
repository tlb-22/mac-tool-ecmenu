import Foundation

/// Finder 触发右键菜单时的框架上下文种类。
///
/// 该值只用于 Finder Extension 边界解释 `FIMenuKind`；跨进程命令使用
/// `FinderContextSnapshot` 的语义化 case，不再携带 Finder 的原始字段组合。
nonisolated enum FinderMenuContext: Int, Sendable {
    /// 在目录内容区域的空白位置打开菜单。
    case container

    /// 在一个或多个选中项目上打开菜单。
    case items

    /// 在 Finder 侧边栏项目上打开菜单。
    case sidebar
}

/// Finder 项目菜单中经过验证的非空选择集合。
nonisolated struct FinderItemSelection: Codable, Equatable, Sendable {
    /// 保持 Finder 原始选择顺序的标准化路径。
    let paths: [String]

    /// 验证并保存一个非空路径集合。
    /// - Parameter paths: Finder 返回的项目路径，顺序会被完整保留。
    /// - Returns: 输入非空时创建选择值，否则返回 `nil`。
    init?(paths: [String]) {
        guard
            !paths.isEmpty,
            paths.allSatisfy({ !$0.isEmpty && $0.hasPrefix("/") })
        else {
            return nil
        }
        self.paths = paths.map(Self.standardizedPath)
    }

    /// 从 Finder URL 验证并保存非空选择集合。
    /// - Parameter urls: Finder 返回的项目 URL。
    /// - Returns: 输入非空时创建选择值，否则返回 `nil`。
    init?(urls: [URL]) {
        self.init(paths: urls.map(\.path))
    }

    /// 把不可变路径恢复为标准化文件 URL，保持 Finder 选择顺序。
    var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
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

    /// 统一标准化一个 Finder 路径。
    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

/// Finder 请求菜单时已经解释完成、可以跨进程传输的语义上下文。
nonisolated enum FinderContextSnapshot: Codable, Equatable, Sendable {
    /// 对当前可见目录本身执行空白区域命令。
    case container(path: String)

    /// 对一个经过验证的非空 Finder 选择集合执行项目命令。
    case items(selection: FinderItemSelection)

    /// 对侧边栏所代表的目录执行命令。
    case sidebar(path: String)

    /// 当前语义上下文包含的全部 URL。
    ///
    /// container 和 sidebar 始终只有一个目录候选；items 保持 Finder 的
    /// 非空选择顺序。文件存在性、目录类型和权限仍由具体 Feature 读取。
    var urls: [URL] {
        switch self {
        case .container(let path), .sidebar(let path):
            return [URL(fileURLWithPath: path).standardizedFileURL]
        case .items(let selection):
            return selection.urls
        }
    }

    /// 请求 schema v3 使用的稳定语义标签。
    private enum Kind: String, Codable {
        case container
        case items
        case sidebar
    }

    /// 显式固定跨进程编码字段，避免依赖编译器生成的 enum 表示。
    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case paths
    }

    /// 解码并验证语义 case 所需的路径约束。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .container, .sidebar:
            let path = try container.decode(String.self, forKey: .path)
            guard let path = Self.validatedPath(path) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: container,
                    debugDescription: "A Finder directory path must be absolute"
                )
            }
            self = kind == .container
                ? .container(path: path)
                : .sidebar(path: path)

        case .items:
            let paths = try container.decode([String].self, forKey: .paths)
            guard let selection = FinderItemSelection(paths: paths) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .paths,
                    in: container,
                    debugDescription: "A Finder item selection must contain absolute paths"
                )
            }
            self = .items(selection: selection)
        }
    }

    /// 编码稳定的语义标签和该 case 唯一允许的路径字段。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .container(let path), .sidebar(let path):
            guard let path = Self.validatedPath(path) else {
                throw EncodingError.invalidValue(
                    path,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "A Finder directory path must be absolute"
                    )
                )
            }
            let kind: Kind
            if case .container = self {
                kind = .container
            } else {
                kind = .sidebar
            }
            try container.encode(kind, forKey: .kind)
            try container.encode(path, forKey: .path)

        case .items(let selection):
            try container.encode(Kind.items, forKey: .kind)
            try container.encode(selection.paths, forKey: .paths)
        }
    }

    /// 验证并标准化 Finder 传输允许的绝对路径。
    private static func validatedPath(_ path: String) -> String? {
        guard !path.isEmpty, path.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

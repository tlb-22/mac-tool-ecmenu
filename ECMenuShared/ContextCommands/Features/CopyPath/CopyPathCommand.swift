import Foundation

/// 请求主应用把 Finder 点击上下文中的绝对路径写入系统剪贴板。
nonisolated struct CopyPathCommand: ContextCommandPayload, Equatable {
    /// 拷贝路径命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "copy-path",
        title: LocalizedStringResource(
            "command.copyPath",
            defaultValue: "Copy Path",
            comment: "Finder command that copies the selected paths"
        ),
        icon: .systemSymbol(
            name: "point.bottomleft.forward.to.point.topright.scurvepath"
        )
    )

    /// 保持 Finder 顺序且已经验证为非空的绝对路径集合。
    let paths: [AbsoluteFilePath]

    /// 只为非空路径集合创建命令。
    init?(paths: [AbsoluteFilePath]) {
        guard !paths.isEmpty else {
            return nil
        }
        self.paths = paths
    }

    /// 解码时重新验证非空约束。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let paths = try container.decode([AbsoluteFilePath].self)
        guard let command = Self(paths: paths) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Copy-path requires at least one absolute path"
            )
        }
        self = command
    }

    /// 只编码有序路径数组。
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(paths)
    }
}

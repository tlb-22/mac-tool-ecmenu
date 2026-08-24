import Foundation

/// 请求主应用根据 Finder 点击上下文创建一个空白 TXT 文件。
nonisolated struct CreateNewTextFileCommand: ContextCommandPayload, Equatable {
    /// 新建 TXT 命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "new-text-file",
        title: "新建 TXT",
        icon: .systemSymbol(name: "text.document")
    )

    /// 菜单期已经解析完成、执行时需要重新验证的目标目录路径。
    let directoryPath: AbsoluteFilePath

    /// 创建指向已解析目标目录的命令。
    init(directoryPath: AbsoluteFilePath) {
        self.directoryPath = directoryPath
    }
}

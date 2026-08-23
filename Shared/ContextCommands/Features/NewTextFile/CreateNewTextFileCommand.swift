import Foundation

/// 请求主应用根据 Finder 点击上下文创建一个空白 TXT 文件。
nonisolated struct CreateNewTextFileCommand: ContextCommandPayload, Equatable {
    /// 新建 TXT 命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "new-text-file",
        title: "新建 TXT",
        icon: .systemSymbol(name: "text.document")
    )

    /// Extension 在 Finder 请求菜单时冻结的上下文。
    let finderContext: FinderContextSnapshot

    /// 创建携带指定 Finder 快照的新建 TXT 命令。
    init(finderContext: FinderContextSnapshot) {
        self.finderContext = finderContext
    }
}

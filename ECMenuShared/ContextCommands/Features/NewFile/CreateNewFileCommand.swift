import Foundation

/// 请求主应用在 Finder 选定的目录中创建指定模板的副本。
nonisolated struct CreateNewFileCommand: ContextCommandPayload, Equatable {
    /// 保留已发布的功能身份，使升级沿用原有显示开关。
    static let descriptor = ContextCommandDescriptor(
        id: "new-text-file",
        title: LocalizedStringResource(
            "command.newFile",
            defaultValue: "New File",
            comment: "Finder submenu for creating files from user templates"
        ),
        icon: .systemSymbol(name: "text.document")
    )

    /// 菜单期已经解析完成、执行时需要重新验证的目标目录路径。
    let directoryPath: AbsoluteFilePath

    /// 菜单打开时绑定的模板身份，不受同名模板或随后改名影响。
    let templateID: FileTemplateID

    /// 创建指向已解析目标目录和模板的命令。
    init(directoryPath: AbsoluteFilePath, templateID: FileTemplateID) {
        self.directoryPath = directoryPath
        self.templateID = templateID
    }
}

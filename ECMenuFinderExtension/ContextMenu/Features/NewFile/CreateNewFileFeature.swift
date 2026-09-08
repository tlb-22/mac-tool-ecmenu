import Foundation

/// 每个模板对应一个稳定 Action，目标目录在当前菜单构建中解析。
final class CreateNewFileFeature: ContextMenuFeature {
    typealias Command = CreateNewFileCommand

    let commandClient: ContextCommandClient

    /// 当前菜单构建时冻结的模板顺序、身份和显示名。
    private let fileTemplates: [FileTemplateMenuItem]

    init(
        commandClient: ContextCommandClient,
        fileTemplates: [FileTemplateMenuItem]
    ) {
        self.commandClient = commandClient
        self.fileTemplates = fileTemplates
    }

    var nodes: [ContextMenuNode<ContextMenuAction<Command>>] {
        [.submenu(
            title: Command.descriptor.title,
            icon: Command.descriptor.icon,
            children: fileTemplates.map { template in
                .item(ContextMenuAction(
                    id: template.id.rawValue.uuidString,
                    title: .verbatim(template.displayName),
                    command: { [self] context in
                        command(templateID: template.id, in: context)
                    }
                ))
            }
        )]
    }

    /// 只捕获模板身份和已经归一化的目标目录。
    func command(
        templateID: FileTemplateID,
        in context: FinderContextMenuEvaluationContext
    ) -> CreateNewFileCommand? {
        guard let directoryPath = Self.directoryPath(in: context) else {
            return nil
        }
        return CreateNewFileCommand(
            directoryPath: directoryPath,
            templateID: templateID
        )
    }

    /// 跟随符号链接重验目标，并把单个文件归一到父目录。
    private static func directoryPath(
        in context: FinderContextMenuEvaluationContext
    ) -> AbsoluteFilePath? {
        guard case .existing(let targetPath, let kind) = context.singleTarget else {
            return nil
        }

        switch context.snapshot {
        case .container, .sidebar:
            return kind == .directory ? targetPath : nil
        case .items:
            if kind == .directory {
                return targetPath
            }
            return AbsoluteFilePath(
                url: targetPath.url.deletingLastPathComponent()
            )
        }
    }
}

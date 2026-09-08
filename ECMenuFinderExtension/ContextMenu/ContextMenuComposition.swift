/// 声明 Finder Extension 中当前产品注册的全部右键功能。
enum ContextMenuComposition {
    /// 同时声明 Finder 菜单布局和对应的具体 Feature。
    /// - Parameters:
    ///   - commandClient: 向主应用投递命令的稳定客户端。
    ///   - fileTemplates: 本次构建使用的当前模板清单。
    /// - Returns: 交给稳定菜单 Controller 的完整声明树。
    static func menu(
        commandClient: ContextCommandClient,
        fileTemplates: [FileTemplateMenuItem]
    ) -> FinderContextMenuDefinition {
        FinderContextMenuDefinition {
            CreateNewFileFeature(
                commandClient: commandClient,
                fileTemplates: fileTemplates
            )
            CopyPathFeature(commandClient: commandClient)
            HideItemsFeature(commandClient: commandClient)
            ShowItemsFeature(commandClient: commandClient)
            CompressImagesFeature(commandClient: commandClient)
            OpenInVSCodeFeature(commandClient: commandClient)
            OpenInITerm2Feature(commandClient: commandClient)
        }
    }
}

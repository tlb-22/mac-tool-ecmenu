/// 声明 Finder Extension 中当前产品注册的全部右键功能。
enum FinderComposition {
    /// 同时声明 Finder 菜单布局和对应的具体 Feature。
    /// - Parameter commandClient: 向主应用投递命令的稳定客户端。
    /// - Returns: 交给稳定菜单 Controller 的完整声明树。
    static func menu(
        commandClient: ContextCommandClient
    ) -> FinderContextMenuDefinition {
        FinderContextMenuDefinition {
            CreateNewTextFileFeature(commandClient: commandClient)
            CopyPathFeature(commandClient: commandClient)
            HideItemsFeature(commandClient: commandClient)
            ShowItemsFeature(commandClient: commandClient)
            CompressImagesFeature(commandClient: commandClient)
            OpenInVSCodeFeature(commandClient: commandClient)
            OpenInITerm2Feature(commandClient: commandClient)
        }
    }
}

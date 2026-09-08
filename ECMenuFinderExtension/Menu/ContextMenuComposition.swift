/**
 集中声明产品当前贡献的菜单能力、显示顺序和层级，将本次模板描述接入新建子菜单。
 组合只接收命令客户端与当前菜单事实，动作可用性由各能力和菜单协调器共同求值。
 */

/// 声明 Finder Extension 中当前产品注册的全部右键功能。
enum ContextMenuComposition {
    /// 同时声明 Finder 菜单布局和对应的具体 Feature。
    /// - Parameters:
    ///   - commandClient: 向主应用投递命令的稳定客户端。
    ///   - newFileTemplates: 本次构建使用的当前模板清单。
    /// - Returns: 交给稳定菜单 Controller 的完整声明树。
    static func menu(
        commandClient: ContextCommandClient,
        newFileTemplates: [FileTemplateMenuItem]
    ) -> FinderContextMenuDefinition {
        FinderContextMenuDefinition {
            CreateNewFileFeature(
                commandClient: commandClient,
                newFileTemplates: newFileTemplates
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

/**
 集中声明产品当前贡献的菜单能力和层级，按配置排列完整能力，将本次模板描述接入新建子菜单。
 组合只接收命令客户端与当前菜单事实，动作可用性由各能力和菜单协调器共同求值。
 */

/// 声明 Finder Extension 中当前产品注册的全部右键功能。
enum ContextMenuComposition {
    /// 同时声明 Finder 菜单布局和对应的具体 Feature。
    /// - Parameters:
    ///   - commandClient: 向主应用投递命令的稳定客户端。
    ///   - newFileTemplates: 本次构建使用的当前模板清单。
    ///   - configuration: 当前快照中的完整命令顺序。
    /// - Returns: 交给稳定菜单 Controller 的完整声明树。
    static func menu(
        commandClient: ContextCommandClient,
        newFileTemplates: [FileTemplateMenuItem],
        configuration: CommandMenuSettings = .standard
    ) -> FinderContextMenuDefinition {
        let features = Dictionary(uniqueKeysWithValues: [
            registration(CreateNewFileFeature(
                commandClient: commandClient,
                newFileTemplates: newFileTemplates
            )),
            registration(CopyPathFeature(commandClient: commandClient)),
            registration(HideItemsFeature(commandClient: commandClient)),
            registration(ShowItemsFeature(commandClient: commandClient)),
            registration(CompressImagesFeature(commandClient: commandClient)),
            registration(OpenInVSCodeFeature(commandClient: commandClient)),
            registration(OpenInITerm2Feature(commandClient: commandClient)),
        ])
        precondition(
            Set(features.keys) == Set(CommandMenuSettings.defaultFeatureIDs),
            "The Finder composition must register every configurable feature"
        )
        return FinderContextMenuDefinition(nodes: configuration.orderedFeatureIDs.flatMap { features[$0]! })
    }

    /// 保留能力身份与完整子树的对应关系，排序不会拆散新建文件子菜单。
    private static func registration<Feature: ContextMenuFeature>(
        _ feature: Feature
    ) -> (ContextCommandFeatureID, [ContextMenuNode<AnyContextMenuAction>]) {
        (Feature.Command.descriptor.id, FinderContextMenuBuilder.buildExpression(feature))
    }
}

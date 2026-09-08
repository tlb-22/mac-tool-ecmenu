/**
 注册独立预览产物可呈现的全部界面场景。
 运行时和截图脚本共同使用这份场景定义，保持稳定标识与呈现入口对应。
 */

/// 集中声明独立 Preview target 可以呈现的全部生产界面场景。
@MainActor
enum PreviewComposition {
    /// 新增一个预览主题时，只在这里注册一行。
    static let previews = [
        ApplicationPreviewDefinition(StatusPageGeneralPreview.self),
        ApplicationPreviewDefinition(StatusPageContextMenuPreview.self),
        ApplicationPreviewDefinition(StatusPageNewFileTemplatesPreview.self),
        ApplicationPreviewDefinition(StatusPageNewFileTemplatesEmptyPreview.self),
        ApplicationPreviewDefinition(StatusPageNewFileTemplatesFailurePreview.self),
        ApplicationPreviewDefinition(READMEStatusPageGeneralPreview.self),
        ApplicationPreviewDefinition(
            READMEStatusPageContextMenuPreview.self
        ),
        ApplicationPreviewDefinition(ImageCompressionSettingsPreview.self),
        ApplicationPreviewDefinition(
            ImageCompressionSettingsValidationErrorPreview.self
        ),
        ApplicationPreviewDefinition(ContextCommandProgressSinglePreview.self),
        ApplicationPreviewDefinition(ContextCommandProgressMultiplePreview.self),
    ]
}

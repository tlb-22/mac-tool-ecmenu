/// 集中声明独立 Preview target 可以呈现的全部生产界面场景。
@MainActor
enum PreviewComposition {
    /// 新增一个预览主题时，只在这里注册一行。
    static let previews = [
        ApplicationPreviewDefinition(StatusPageGeneralPreview.self),
        ApplicationPreviewDefinition(StatusPageContextMenuPreview.self),
        ApplicationPreviewDefinition(ImageCompressionSettingsPreview.self),
        ApplicationPreviewDefinition(
            ImageCompressionSettingsValidationErrorPreview.self
        ),
        ApplicationPreviewDefinition(ContextCommandProgressSinglePreview.self),
        ApplicationPreviewDefinition(ContextCommandProgressMultiplePreview.self),
    ]
}

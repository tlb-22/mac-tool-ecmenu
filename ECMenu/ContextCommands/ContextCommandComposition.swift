/// 声明主应用中每种产品命令对应的功能 Handler。
@MainActor
enum ContextCommandComposition {
    /// 整个主应用生命周期共用的模板库；构造不执行磁盘读写。
    static let fileTemplateLibrary = FileTemplateLibrary()

    /// 当前产品支持的全部主应用执行端。
    static let handlers = ContextCommandHandlers {
        CreateNewFileHandler(library: fileTemplateLibrary)
        CopyPathHandler()
        HideItemsHandler()
        ShowItemsHandler()
        CompressImagesHandler()
        OpenInVSCodeHandler()
        OpenInITerm2Handler()
    }

    static var descriptors: [ContextCommandDescriptor] { handlers.descriptors }
}

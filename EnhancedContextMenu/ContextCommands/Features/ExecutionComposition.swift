/// 声明主应用中每种产品命令对应的功能 Handler。
@MainActor
enum ExecutionComposition {
    /// 当前产品支持的全部主应用执行端。
    static let handlers = ContextCommandHandlers {
        CreateNewTextFileHandler()
        CopyPathHandler()
        HideItemsHandler()
        ShowItemsHandler()
        CompressImagesHandler()
        OpenInVSCodeHandler()
        OpenInITerm2Handler()
    }
}

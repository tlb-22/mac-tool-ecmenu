import Foundation

/// 请求主应用压缩 Finder 中选中的一张或多张图片。
nonisolated struct CompressImagesCommand: ContextCommandPayload, Equatable {
    /// 压缩图片命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "compress-images",
        title: LocalizedStringResource(
            "command.compressImages",
            defaultValue: "Compress Images",
            comment: "Finder command that compresses the selected images"
        ),
        icon: .systemSymbol(name: "photo.badge.arrow.down")
    )

    /// Extension 在 Finder 请求菜单时验证的非空图片选择。
    let selection: FinderItemSelection

    /// 创建携带指定项目选择的图片压缩命令。
    init(selection: FinderItemSelection) {
        self.selection = selection
    }
}

import Foundation

/// 请求主应用压缩 Finder 中选中的一张或多张图片。
nonisolated struct CompressImagesCommand: ContextCommandPayload, Equatable {
    /// 压缩图片命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "compress-images",
        title: "压缩图片",
        icon: .systemSymbol(name: "photo.badge.arrow.down")
    )

    /// Extension 在 Finder 请求菜单时冻结的项目上下文。
    let finderContext: FinderContextSnapshot

    /// 创建携带指定 Finder 快照的图片压缩命令。
    init(finderContext: FinderContextSnapshot) {
        self.finderContext = finderContext
    }
}

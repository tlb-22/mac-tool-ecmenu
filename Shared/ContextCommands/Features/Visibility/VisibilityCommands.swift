import Foundation

/// 请求主应用隐藏 Finder 点击上下文中的对象。
nonisolated struct HideItemsCommand: ContextCommandPayload, Equatable {
    /// 隐藏命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "hide-items",
        title: "隐藏项目",
        icon: .systemSymbol(name: "eye.slash")
    )

    /// Extension 在 Finder 请求菜单时冻结的上下文。
    let finderContext: FinderContextSnapshot

    /// 创建携带指定 Finder 快照的隐藏命令。
    init(finderContext: FinderContextSnapshot) {
        self.finderContext = finderContext
    }
}

/// 请求主应用显示 Finder 点击上下文中的对象。
nonisolated struct ShowItemsCommand: ContextCommandPayload, Equatable {
    /// 显示命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "show-items",
        title: "显示项目",
        icon: .systemSymbol(name: "eye")
    )

    /// Extension 在 Finder 请求菜单时冻结的上下文。
    let finderContext: FinderContextSnapshot

    /// 创建携带指定 Finder 快照的显示命令。
    init(finderContext: FinderContextSnapshot) {
        self.finderContext = finderContext
    }
}

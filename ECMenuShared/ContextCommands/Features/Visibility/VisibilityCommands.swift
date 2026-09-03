import Foundation

/// 请求主应用隐藏 Finder 点击上下文中的对象。
nonisolated struct HideItemsCommand: ContextCommandPayload, Equatable {
    /// 隐藏命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "hide-items",
        title: LocalizedStringResource(
            "command.hideItems",
            defaultValue: "Hide Items",
            comment: "Finder command that hides the selected items"
        ),
        icon: .systemSymbol(name: "eye.slash")
    )

    /// 菜单期验证过的非空项目选择。
    let selection: FinderItemSelection

    /// 创建携带指定项目选择的隐藏命令。
    init(selection: FinderItemSelection) {
        self.selection = selection
    }
}

/// 请求主应用显示 Finder 点击上下文中的对象。
nonisolated struct ShowItemsCommand: ContextCommandPayload, Equatable {
    /// 显示命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "show-items",
        title: LocalizedStringResource(
            "command.showItems",
            defaultValue: "Show Items",
            comment: "Finder command that reveals the selected hidden items"
        ),
        icon: .systemSymbol(name: "eye")
    )

    /// 菜单期验证过的非空项目选择。
    let selection: FinderItemSelection

    /// 创建携带指定项目选择的显示命令。
    init(selection: FinderItemSelection) {
        self.selection = selection
    }
}

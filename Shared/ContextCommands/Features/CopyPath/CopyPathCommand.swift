import Foundation

/// 请求主应用把 Finder 点击上下文中的绝对路径写入系统剪贴板。
nonisolated struct CopyPathCommand: ContextCommandPayload, Equatable {
    /// 拷贝路径命令唯一一份稳定身份、产品名称与菜单图标。
    static let descriptor = ContextCommandDescriptor(
        id: "copy-path",
        title: "拷贝路径",
        icon: .systemSymbol(
            name: "point.bottomleft.forward.to.point.topright.scurvepath"
        )
    )

    /// Extension 在 Finder 请求菜单时冻结的上下文。
    let finderContext: FinderContextSnapshot

    /// 创建携带指定 Finder 快照的拷贝路径命令。
    init(finderContext: FinderContextSnapshot) {
        self.finderContext = finderContext
    }
}

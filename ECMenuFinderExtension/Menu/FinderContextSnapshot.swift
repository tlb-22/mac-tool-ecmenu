/**
 表达 Extension 已解释完成的菜单事件，分别承载背景目录、非空项目选择或侧栏目录。
 快照只保留不可变路径语义，供菜单判定和动作准备共同使用；文件状态由事实读取提供。
 */

import Foundation

/// Finder 触发右键菜单时的框架上下文种类。
nonisolated enum FinderMenuContext: Sendable {
    /// 在目录内容区域的空白位置打开菜单。
    case container

    /// 在一个或多个选中项目上打开菜单。
    case items

    /// 在 Finder 侧边栏项目上打开菜单。
    case sidebar
}

/// Finder 请求菜单时已经解释完成、只在 Extension 内存活的语义快照。
nonisolated enum FinderContextSnapshot: Equatable, Sendable {
    /// 对当前可见目录本身执行空白区域命令。
    case container(path: AbsoluteFilePath)

    /// 对一个经过验证的非空 Finder 选择集合执行项目命令。
    case items(selection: FinderItemSelection)

    /// 对侧边栏所代表的目录执行命令。
    case sidebar(path: AbsoluteFilePath)

    /// 当前语义上下文中保持 Finder 顺序的强类型绝对路径。
    var absolutePaths: [AbsoluteFilePath] {
        switch self {
        case .container(let path), .sidebar(let path):
            return [path]
        case .items(let selection):
            return selection.absolutePaths
        }
    }
}

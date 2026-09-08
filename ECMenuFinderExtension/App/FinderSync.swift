/**
 连接 Finder principal object 的生命周期、菜单请求与 Objective-C 动作回调。
 配置副本、命令客户端、菜单协调器和卷登记各自承担具体职责，随当前 Extension 实例存活。
 */

import AppKit
import FinderSync

/// Finder Sync Extension 的主对象，负责注册目录范围、构建菜单并接收菜单 action。
final class FinderSync: FIFinderSync {
    /// Extension 侧的菜单配置只读副本。
    private let commandMenuConfig = CommandMenuConfigReplica()

    /// 将类型化右键命令投递给主应用的通用客户端。
    private let commandClient = ContextCommandClient()

    /// 卷范围适配器随 principal object 存活。
    private lazy var directoryRegistration = FinderDirectoryRegistration()

    /// 解释产品菜单声明，并通过菜单项绑定的上下文路由 action。
    private lazy var contextMenuController = FinderContextMenuController(
        makeMenu: { [commandClient, commandMenuConfig] in
            ContextMenuComposition.menu(
                commandClient: commandClient,
                newFileTemplates: commandMenuConfig.newFileTemplates
            )
        },
        configuration: commandMenuConfig
    )

    /// Finder 框架初始化完成后创建范围登记会话。
    override init() {
        super.init()
        _ = directoryRegistration
    }

    // MARK: - ==================== Finder 菜单与 action ====================

    /// 根据 Finder 提供的菜单类型组装当前上下文菜单。
    /// - Parameter menuKind: Finder 正在构建的上下文类型。
    /// - Returns: 至少包含一个功能项时返回菜单，否则返回 `nil`。
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        contextMenuController.menu(
            for: menuKind,
            action: #selector(performContextCommand(_:))
        )
    }

    /// 接收 Finder 调用的通用 Objective-C action，并按菜单项上下文路由。
    /// - Parameter sender: Finder 返回的菜单项。
    @IBAction func performContextCommand(_ sender: NSMenuItem) {
        contextMenuController.perform(sender)
    }
}

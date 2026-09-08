/**
 规定能力向通用菜单树贡献类型化叶子的接口，并为只有一个动作的能力提供简洁默认组合。
 共享命令声明提供稳定身份与产品信息，具体能力只负责在给定上下文中准备参数。
 */

import Foundation

/// 可以声明 Finder 菜单树并构造类型化命令的增量功能。
protocol ContextMenuFeature: AnyObject {
    /// 当前 Feature 所有 Action 共用的跨进程命令类型。
    associatedtype Command: ContextCommandPayload

    /// 向主应用投递当前功能命令的客户端。
    var commandClient: ContextCommandClient { get }

    /// 当前 Feature 独立拥有的叶子、分隔线和子菜单。
    var nodes: [ContextMenuNode<ContextMenuAction<Command>>] { get }
}

/// 只有一个菜单 Action 的 Feature 使用的简洁协议。
/// 返回 `nil` 同时表示当前上下文不显示该命令。
protocol SingleActionContextMenuFeature: ContextMenuFeature {
    /// 在本次菜单上下文中准备可执行命令。
    func command(
        in context: FinderContextMenuEvaluationContext
    ) -> Command?
}

extension SingleActionContextMenuFeature {
    /// 从共享 descriptor 自动生成单一叶子。
    var nodes: [ContextMenuNode<ContextMenuAction<Command>>] {
        let descriptor = Command.descriptor
        return [
            .item(
                ContextMenuAction(
                    id: "primary",
                    title: descriptor.title,
                    icon: descriptor.icon,
                    command: { [self] context in
                        command(in: context)
                    }
                )
            ),
        ]
    }
}

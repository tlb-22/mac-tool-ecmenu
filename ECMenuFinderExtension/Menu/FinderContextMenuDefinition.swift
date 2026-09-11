/**
 为产品菜单提供声明式组合入口，将完整能力、分隔线和嵌套子菜单收敛为同一棵运行时树。
 构造时验证动作身份唯一，类型擦除后的叶子仍保留各自命令准备行为。
 */

import Foundation

/// 保存 Finder 产品顺序、层级和可执行叶子的不可变声明。
struct FinderContextMenuDefinition {
    /// 产品声明和运行时准备共用的递归菜单树。
    let nodes: [ContextMenuNode<AnyContextMenuAction>]

    /// 使用一棵声明树构造并验证产品菜单。
    init(
        @FinderContextMenuBuilder content: () -> [
            ContextMenuNode<AnyContextMenuAction>
        ]
    ) {
        self.init(nodes: content())
    }

    /// 使用已经按配置排列的完整能力子树构造菜单。
    init(nodes: [ContextMenuNode<AnyContextMenuAction>]) {
        let actionIDs = nodes
            .flatMap { $0.items }
            .map(\.descriptor.id)
        precondition(
            Set(actionIDs).count == actionIDs.count,
            "A Finder context-menu Action was registered more than once"
        )
        self.nodes = nodes
    }
}

/// 在 Finder 声明树中插入一条系统分隔线。
struct ContextMenuSeparator {
    /// 创建一个无状态的分隔线声明。
    init() {}
}

/// 在 Finder 产品声明树中递归组合一组完整 Feature。
struct FinderContextMenuSubmenu {
    /// 子菜单的固定产品标题。
    let title: LocalizedStringResource

    /// 子菜单内部的递归节点。
    let nodes: [ContextMenuNode<AnyContextMenuAction>]

    /// 使用 Finder 产品 builder 创建嵌套菜单。
    init(
        _ title: LocalizedStringResource,
        @FinderContextMenuBuilder content: () -> [
            ContextMenuNode<AnyContextMenuAction>
        ]
    ) {
        precondition(!title.key.isEmpty)
        self.title = title
        nodes = content()
    }
}

/// 把顺序书写的具体 Feature 直接组合为 Finder 菜单声明树。
@resultBuilder
enum FinderContextMenuBuilder {
    /// result builder 的统一中间类型。
    typealias Component = [ContextMenuNode<AnyContextMenuAction>]

    /// 一个具体 Feature 贡献自己的完整菜单子树和运行时 Action。
    static func buildExpression<Feature: ContextMenuFeature>(
        _ expression: Feature
    ) -> Component {
        let featureID = Feature.Command.descriptor.id
        let nodes = expression.nodes.map { node in
            node.mapItems { action in
                AnyContextMenuAction(
                    action,
                    featureID: featureID,
                    commandClient: expression.commandClient
                )
            }
        }
        return nodes
    }

    /// 把系统分隔线加入产品布局，不注册 Feature。
    static func buildExpression(_: ContextMenuSeparator) -> Component {
        [.separator]
    }

    /// 把一组完整 Feature 的子菜单递归嵌入产品布局。
    static func buildExpression(
        _ expression: FinderContextMenuSubmenu
    ) -> Component {
        [.submenu(title: expression.title, children: expression.nodes)]
    }

    /// 按书写顺序拼接同级布局和 Feature。
    static func buildBlock(_ components: Component...) -> Component {
        components.flatMap { $0 }
    }
}

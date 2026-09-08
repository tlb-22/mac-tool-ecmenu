/**
 验证声明式菜单树在过滤不可见功能后的递归规范化。
 以纯树样例检查空子菜单、分隔线、声明顺序与嵌套结构。
 */

import XCTest
@testable import ECMenuFinderExtension

/// 验证声明式菜单布局的递归过滤和结构规范化。
final class ContextMenuLayoutTests: XCTestCase {
    /// 隐藏功能不应留下空子菜单、首尾分隔线或连续分隔线。
    func testVisibilityFilteringNormalizesStructure() {
        let nodes: [ContextMenuNode<TestFeatureID>] = [
            .separator,
            .item(.first),
            .separator,
            .separator,
            .submenu(
                title: "开发工具",
                children: [
                    .separator,
                    .item(.second),
                    .separator,
                    .item(.third),
                    .separator,
                ]
            ),
            .separator,
        ]

        XCTAssertEqual(
            ContextMenuNodeResolver.compactMapItems(in: nodes) {
                $0 == .second ? $0 : nil
            },
            [
                .submenu(
                    title: "开发工具",
                    children: [.item(.second)]
                ),
            ]
        )
    }

    /// 没有任何可见功能时，布局应解析为空而不是只剩装饰节点。
    func testCompletelyHiddenLayoutIsEmpty() {
        let nodes: [ContextMenuNode<TestFeatureID>] = [
            .item(.first),
            .separator,
            .submenu(
                title: "更多",
                children: [.item(.second)]
            ),
        ]

        XCTAssertTrue(
            ContextMenuNodeResolver.compactMapItems(in: nodes) { _ in
                Optional<TestFeatureID>.none
            }.isEmpty
        )
    }

    /// 可见功能应保持声明顺序和递归层级。
    func testDeclarationOrderAndNestingArePreserved() {
        let nodes: [ContextMenuNode<TestFeatureID>] = [
            .item(.first),
            .separator,
            .submenu(
                title: "更多",
                children: [
                    .item(.second),
                    .item(.third),
                ]
            ),
        ]

        XCTAssertEqual(
            ContextMenuNodeResolver.compactMapItems(in: nodes) { $0 },
            [
                .item(.first),
                .separator,
                .submenu(
                    title: "更多",
                    children: [
                        .item(.second),
                        .item(.third),
                    ]
                ),
            ]
        )
    }
}

/// 仅用于验证通用布局解释器不依赖产品功能枚举。
nonisolated private enum TestFeatureID: Equatable, Sendable {
    case first
    case second
    case third
}

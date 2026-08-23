import XCTest
@testable import EnhancedContextMenuFinderExtension

/// 验证声明式菜单布局的递归过滤和结构规范化。
final class ContextMenuLayoutTests: XCTestCase {
    /// 隐藏功能不应留下空子菜单、首尾分隔线或连续分隔线。
    func testVisibilityFilteringNormalizesStructure() {
        let layout: [ContextMenuLayout<TestFeatureID>] = [
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
            ContextMenuLayoutResolver.visibleElements(
                in: layout,
                isItemVisible: { $0 == .second }
            ),
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
        let layout: [ContextMenuLayout<TestFeatureID>] = [
            .item(.first),
            .separator,
            .submenu(
                title: "更多",
                children: [.item(.second)]
            ),
        ]

        XCTAssertTrue(
            ContextMenuLayoutResolver.visibleElements(
                in: layout,
                isItemVisible: { _ in false }
            ).isEmpty
        )
    }

    /// 可见功能应保持声明顺序和递归层级。
    func testDeclarationOrderAndNestingArePreserved() {
        let layout: [ContextMenuLayout<TestFeatureID>] = [
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
            ContextMenuLayoutResolver.visibleElements(
                in: layout,
                isItemVisible: { _ in true }
            ),
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

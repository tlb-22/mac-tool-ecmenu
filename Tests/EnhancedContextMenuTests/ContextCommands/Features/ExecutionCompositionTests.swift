import XCTest
@testable import EnhancedContextMenu

/// 验证主应用声明式 Handler 注册也是状态页的产品目录来源。
@MainActor
final class ExecutionCompositionTests: XCTestCase {
    /// Handler 注册顺序应自动贡献主应用中的完整产品目录。
    func testCurrentProductHandlers() throws {
        XCTAssertEqual(
            ExecutionComposition.handlers.descriptors.map(\.id.rawValue),
            ProductContextCommandExpectation.featureIDs
        )
        XCTAssertEqual(
            ExecutionComposition.handlers.descriptors,
            [
                CreateNewTextFileCommand.descriptor,
                CopyPathCommand.descriptor,
                HideItemsCommand.descriptor,
                ShowItemsCommand.descriptor,
                CompressImagesCommand.descriptor,
                OpenInVSCodeCommand.descriptor,
                OpenInITerm2Command.descriptor,
            ]
        )
        XCTAssertEqual(
            ExecutionComposition.handlers.descriptors.map(\.title),
            [
                "新建 TXT",
                "拷贝路径",
                "隐藏项目",
                "显示项目",
                "压缩图片",
                "进入 Visual Studio Code",
                "进入 iTerm2",
            ]
        )
        XCTAssertEqual(
            ExecutionComposition.handlers.descriptors.map(\.icon),
            [
                .systemSymbol(name: "text.document"),
                .systemSymbol(
                    name: "point.bottomleft.forward.to.point.topright.scurvepath"
                ),
                .systemSymbol(name: "eye.slash"),
                .systemSymbol(name: "eye"),
                .systemSymbol(name: "photo.badge.arrow.down"),
                .requiredApplication,
                .requiredApplication,
            ]
        )
    }
}

import XCTest
@testable import ECMenu

/// 验证主应用声明式 Handler 注册也是状态页的产品目录来源。
@MainActor
final class ContextCommandCompositionTests: XCTestCase {
    /// Handler 注册顺序应自动贡献主应用中的完整产品目录。
    func testCurrentProductHandlers() throws {
        XCTAssertEqual(
            ContextCommandComposition.handlers.descriptors.map(\.id.rawValue),
            ProductContextCommandExpectation.featureIDs
        )
        XCTAssertEqual(
            ContextCommandComposition.handlers.descriptors,
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
            ContextCommandComposition.handlers.descriptors.map(\.icon),
            [
                .systemSymbol(name: "text.document"),
                .systemSymbol(
                    name: "point.bottomleft.forward.to.point.topright.scurvepath"
                ),
                .systemSymbol(name: "eye.slash"),
                .systemSymbol(name: "eye"),
                .systemSymbol(name: "photo.badge.arrow.down"),
                .application(OpenInVSCodeCommand.applicationRequirement),
                .application(OpenInITerm2Command.applicationRequirement),
            ]
        )
    }
}

/**
 验证主应用 Handler 注册覆盖完整产品命令目录并保持声明顺序。
 以显式依赖构造命令装配，检查状态页目录与可执行能力使用同一来源。
 */

import XCTest
@testable import ECMenu

/// 验证主应用声明式 Handler 注册也是状态页的产品目录来源。
@MainActor
final class ContextCommandCompositionTests: XCTestCase {
    /// Handler 注册顺序应自动贡献主应用中的完整产品目录。
    func testCurrentProductHandlers() throws {
        let handlers = ContextCommandComposition.makeHandlers(dependencies: ContextCommandDependencies(
            readTemplate: { throw FileTemplateLibraryError.templateNotFound($0) },
            requestImageSettings: { nil }
        ))
        XCTAssertEqual(handlers.descriptors, ContextCommandComposition.descriptors)
        XCTAssertEqual(
            handlers.descriptors.map(\.id.rawValue),
            ProductContextCommandExpectation.featureIDs
        )
        XCTAssertEqual(
            handlers.descriptors,
            [
                CreateNewFileCommand.descriptor,
                CopyPathCommand.descriptor,
                HideItemsCommand.descriptor,
                ShowItemsCommand.descriptor,
                CompressImagesCommand.descriptor,
                OpenInVSCodeCommand.descriptor,
                OpenInITerm2Command.descriptor,
            ]
        )
        XCTAssertEqual(
            handlers.descriptors.map(\.icon),
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
        XCTAssertEqual(
            handlers.descriptors.compactMap(\.requiredApplication),
            [
                OpenInVSCodeCommand.applicationRequirement,
                OpenInITerm2Command.applicationRequirement,
            ]
        )
    }
}

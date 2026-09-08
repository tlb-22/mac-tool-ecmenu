/**
 验证设置页图标的统一尺寸、语义居中和颜色模式。
 直接渲染不同 Symbol 样例，检查图标输出遵守生产页面的画布度量。
 */

import AppKit
import XCTest
@testable import ECMenu

/// 验证状态页全部图标使用统一尺度、语义居中与颜色模式。
@MainActor
final class StatusPageIconRendererTests: XCTestCase {
    /// 单色、分层和带 badge 的 Symbol 都应使用统一设置页度量。
    func testSystemSymbolsUseUnifiedStatusPageMetrics() throws {
        let plainImage = try XCTUnwrap(
            StatusPageIconRenderer.hierarchicalSystemSymbol(named: "photo")
        )
        let badgedImage = try XCTUnwrap(
            StatusPageIconRenderer.hierarchicalSystemSymbol(
                named: "photo.badge.arrow.down"
            )
        )
        let monochromeImage = try XCTUnwrap(
            StatusPageIconRenderer.monochromeSystemSymbol(named: "gearshape")
        )
        let canvasSize = StatusPageIconRenderer.canvasSize
        let canvasRect = NSRect(origin: .zero, size: canvasSize)

        XCTAssertEqual(plainImage.size, canvasSize)
        XCTAssertEqual(badgedImage.size, canvasSize)
        XCTAssertEqual(monochromeImage.size, canvasSize)
        XCTAssertEqual(plainImage.alignmentRect, canvasRect)
        XCTAssertEqual(badgedImage.alignmentRect, canvasRect)
        XCTAssertFalse(plainImage.isTemplate)
        XCTAssertTrue(monochromeImage.isTemplate)
    }
}

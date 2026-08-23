import AppKit
import XCTest
@testable import EnhancedContextMenu

/// 验证两个产品 target 共用的 AppKit 图标画布变换。
@MainActor
final class AppKitIconCanvasRendererTests: XCTestCase {
    /// 语义居中只能平移源图，不得把溢出内容缩小进画布。
    func testSemanticCenteringPreservesNaturalSizeAndOverhang() {
        let canvasSize = NSSize(width: 20, height: 20)
        let canvasRect = NSRect(origin: .zero, size: canvasSize)
        let sourceSize = NSSize(width: 22, height: 20)
        let alignmentRect = canvasRect

        let drawingRect =
            AppKitIconCanvasRenderer.semanticSymbolDrawingRect(
                sourceSize: sourceSize,
                alignmentRect: alignmentRect,
                canvasSize: canvasSize
            )

        XCTAssertEqual(drawingRect.size, sourceSize)
        XCTAssertEqual(
            drawingRect.minX + alignmentRect.midX,
            canvasRect.midX,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            drawingRect.minY + alignmentRect.midY,
            canvasRect.midY,
            accuracy: 0.000_001
        )
        XCTAssertGreaterThan(drawingRect.maxX, canvasRect.maxX)
    }

    /// 等比适配应缩小大图、保持居中，并且默认不放大小图。
    func testProportionalFittingPreservesAspectRatioWithoutUpscaling() throws {
        let canvasSize = NSSize(width: 20, height: 20)
        let largeRect = try XCTUnwrap(
            AppKitIconCanvasRenderer.proportionallyFittedDrawingRect(
                sourceSize: NSSize(width: 40, height: 20),
                canvasSize: canvasSize
            )
        )

        XCTAssertEqual(largeRect.size, NSSize(width: 20, height: 10))
        XCTAssertEqual(largeRect.midX, canvasSize.width / 2)
        XCTAssertEqual(largeRect.midY, canvasSize.height / 2)

        let smallSource = NSSize(width: 4, height: 2)
        let smallRect = try XCTUnwrap(
            AppKitIconCanvasRenderer.proportionallyFittedDrawingRect(
                sourceSize: smallSource,
                canvasSize: canvasSize
            )
        )
        XCTAssertEqual(smallRect.size, smallSource)
        XCTAssertEqual(smallRect.midX, canvasSize.width / 2)
        XCTAssertEqual(smallRect.midY, canvasSize.height / 2)
        XCTAssertNil(
            AppKitIconCanvasRenderer.proportionallyFittedDrawingRect(
                sourceSize: .zero,
                canvasSize: canvasSize
            )
        )
    }

    /// 烘焙后的图像应采用调用端画布，并保留 template 颜色语义。
    func testRenderedImageUsesCanvasAndPreservesTemplateState() throws {
        let sourceImage = NSImage(size: NSSize(width: 8, height: 4))
        sourceImage.isTemplate = true
        let canvasSize = NSSize(width: 20, height: 20)

        let image = try XCTUnwrap(
            AppKitIconCanvasRenderer.proportionallyFittedImage(
                sourceImage,
                canvasSize: canvasSize
            )
        )

        XCTAssertEqual(image.size, canvasSize)
        XCTAssertEqual(
            image.alignmentRect,
            NSRect(origin: .zero, size: canvasSize)
        )
        XCTAssertTrue(image.isTemplate)
    }
}

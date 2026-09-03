import AppKit

/// 将 AppKit 图像按稳定几何规则烘焙到调用端指定的画布。
///
/// 调用端负责生成带有场景字号、颜色和比例配置的源图，并继续拥有缓存、
/// 降级图标与界面度量；本类型只处理两个产品 target 必须一致的图像变换。
enum AppKitIconCanvasRenderer {
    /// 保持 SF Symbol 的自然尺寸，并把系统语义主体中心移动到画布中心。
    ///
    /// `alignmentRect` 外的 badge 等附属像素不会参与居中，也不会触发缩放；
    /// 超出画布的部分由图像边界自然裁切。
    /// - Parameters:
    ///   - sourceImage: 已经应用调用端 Symbol 配置的源图像。
    ///   - canvasSize: 调用端需要的最终图像尺寸。
    /// - Returns: 语义居中的画布图像；任一度量无效时为 `nil`。
    static func semanticCenteredSymbol(
        _ sourceImage: NSImage,
        canvasSize: NSSize
    ) -> NSImage? {
        let sourceSize = sourceImage.size
        let alignmentRect = sourceImage.alignmentRect
        guard
            isValid(sourceSize),
            isValid(canvasSize),
            alignmentRect.width > 0,
            alignmentRect.height > 0
        else {
            return nil
        }

        return draw(
            sourceImage,
            on: canvasSize,
            in: semanticSymbolDrawingRect(
                sourceSize: sourceSize,
                alignmentRect: alignmentRect,
                canvasSize: canvasSize
            )
        )
    }

    /// 保持宽高比地把图像居中放入画布，且不放大小图。
    /// - Parameters:
    ///   - sourceImage: 需要适配画布的源图像。
    ///   - canvasSize: 调用端需要的最终图像尺寸。
    /// - Returns: 等比居中的画布图像；任一尺寸无效时为 `nil`。
    static func proportionallyFittedImage(
        _ sourceImage: NSImage,
        canvasSize: NSSize
    ) -> NSImage? {
        guard let drawingRect = proportionallyFittedDrawingRect(
            sourceSize: sourceImage.size,
            canvasSize: canvasSize
        ) else {
            return nil
        }

        return draw(sourceImage, on: canvasSize, in: drawingRect)
    }

    /// 计算不缩放 Symbol、只移动其语义主体中心的绘制区域。
    /// - Parameters:
    ///   - sourceSize: 系统生成的自然图像尺寸。
    ///   - alignmentRect: 系统提供的语义主体对齐区域。
    ///   - canvasSize: 最终画布尺寸。
    /// - Returns: 尺寸与源图一致、仅改变原点的绘制区域。
    static func semanticSymbolDrawingRect(
        sourceSize: NSSize,
        alignmentRect: NSRect,
        canvasSize: NSSize
    ) -> NSRect {
        NSRect(
            x: canvasSize.width / 2 - alignmentRect.midX,
            y: canvasSize.height / 2 - alignmentRect.midY,
            width: sourceSize.width,
            height: sourceSize.height
        )
    }

    /// 计算图像在画布中的等比居中区域。
    /// - Parameters:
    ///   - sourceSize: 源图像尺寸。
    ///   - canvasSize: 最终画布尺寸。
    /// - Returns: 等比居中的绘制区域；任一尺寸无效时为 `nil`。
    static func proportionallyFittedDrawingRect(
        sourceSize: NSSize,
        canvasSize: NSSize
    ) -> NSRect? {
        guard isValid(sourceSize), isValid(canvasSize) else {
            return nil
        }

        let fittingScale = min(
            canvasSize.width / sourceSize.width,
            canvasSize.height / sourceSize.height
        )
        let scale = min(1, fittingScale)
        let fittedSize = NSSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        return NSRect(
            x: (canvasSize.width - fittedSize.width) / 2,
            y: (canvasSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    /// 把源图按给定区域绘制到新画布，并保留 template 语义。
    private static func draw(
        _ sourceImage: NSImage,
        on canvasSize: NSSize,
        in drawingRect: NSRect
    ) -> NSImage {
        let sourceRect = NSRect(origin: .zero, size: sourceImage.size)
        let image = NSImage(size: canvasSize, flipped: false) { _ in
            sourceImage.draw(
                in: drawingRect,
                from: sourceRect,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }
        image.isTemplate = sourceImage.isTemplate
        return image
    }

    /// 判断一个逻辑图像尺寸是否可以参与除法和绘制。
    private static func isValid(_ size: NSSize) -> Bool {
        size.width > 0 && size.height > 0
    }
}

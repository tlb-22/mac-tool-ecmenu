/**
 解析进度任务描述中的系统图标或应用图标。
 将图标查找与缓存集中在进度展示边界。
 */

import AppKit
import Foundation

/// 把共享命令的图标声明解析为统一正方形画布。
@MainActor
final class ContextCommandProgressIconResolver {
    /// SF Symbol 和应用图标均按稳定来源缓存。
    private var cache: [String: NSImage] = [:]

    /// 解析 descriptor 的真实图标，外部应用缺失时使用统一占位符。
    func image(for descriptor: ContextCommandDescriptor) -> NSImage? {
        switch descriptor.icon {
        case .systemSymbol(let name):
            return systemSymbol(named: name)

        case .application(let requirement):
            guard
                let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: requirement.bundleIdentifier
                )
            else {
                return systemSymbol(named: "questionmark.app.dashed")
            }

            let cacheKey = "application:\(requirement.bundleIdentifier)"
            if let cachedImage = cache[cacheKey] {
                return cachedImage
            }

            let sourceImage = NSWorkspace.shared.icon(
                forFile: applicationURL.path
            )
            guard let image = centeredImage(sourceImage) else {
                return systemSymbol(named: "questionmark.app.dashed")
            }
            cache[cacheKey] = image
            return image
        }
    }

    /// 按系统标签颜色创建 SF Symbol。
    private func systemSymbol(named name: String) -> NSImage? {
        let cacheKey = "symbol:\(name)"
        if let cachedImage = cache[cacheKey] {
            return cachedImage
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 30,
            weight: .regular
        ).applying(
            NSImage.SymbolConfiguration(hierarchicalColor: .labelColor)
        )
        guard
            let sourceImage = NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(configuration),
            let image = centeredImage(sourceImage)
        else {
            return nil
        }

        cache[cacheKey] = image
        return image
    }

    /// 保持比例缩放并居中，非正方形图标不被拉伸或裁切。
    private func centeredImage(_ sourceImage: NSImage) -> NSImage? {
        let sourceSize = sourceImage.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }

        let canvasLength = ContextCommandProgressWindowLayout.iconCanvasLength
        let canvasSize = NSSize(width: canvasLength, height: canvasLength)
        let maximumIconLength = canvasLength - 4
        let scale = min(
            maximumIconLength / sourceSize.width,
            maximumIconLength / sourceSize.height
        )
        let fittedSize = NSSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let fittedRect = NSRect(
            x: (canvasLength - fittedSize.width) / 2,
            y: (canvasLength - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )

        let image = NSImage(size: canvasSize, flipped: false) { _ in
            sourceImage.draw(
                in: fittedRect,
                from: NSRect(origin: .zero, size: sourceSize),
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
}

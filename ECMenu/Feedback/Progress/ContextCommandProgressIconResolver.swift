/**
 解析进度任务描述中的系统符号、应用或文件类型图标。
 图标查找、场景配置与缓存留在进度展示边界，画布变换复用共享的语义居中与等比适配规则。
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
        case .fileType(let filenameExtension):
            return AppKitIconCanvasRenderer.proportionallyFittedImage(
                FileTypeIconProvider.icon(forFilenameExtension: filenameExtension),
                canvasSize: ContextCommandProgressWindowLayout.iconCanvasSize
            )

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
            guard let image = AppKitIconCanvasRenderer.proportionallyFittedImage(
                sourceImage,
                canvasSize: ContextCommandProgressWindowLayout.iconCanvasSize
            ) else {
                return systemSymbol(named: "questionmark.app.dashed")
            }
            cache[cacheKey] = image
            return image
        }
    }

    /// 按场景字号和系统标签颜色生成 SF Symbol，保持自然尺寸并按语义主体居中。
    private func systemSymbol(named name: String) -> NSImage? {
        let cacheKey = "symbol:\(name)"
        if let cachedImage = cache[cacheKey] {
            return cachedImage
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: ContextCommandProgressWindowLayout.iconSymbolPointSize,
            weight: .regular
        ).applying(
            NSImage.SymbolConfiguration(hierarchicalColor: .labelColor)
        )
        guard
            let sourceImage = NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(configuration),
            let image = AppKitIconCanvasRenderer.semanticCenteredSymbol(
                sourceImage,
                canvasSize: ContextCommandProgressWindowLayout.iconCanvasSize
            )
        else {
            return nil
        }

        cache[cacheKey] = image
        return image
    }
}

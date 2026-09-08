/**
 把符号和应用图标适配为 Finder 菜单槽位可用的图像，统一源图生成、画布度量与缺失处理。
 渲染器独占跨菜单图像缓存，几何变换复用共享画布原语。
 */

import AppKit
import Foundation

/// 将菜单图标适配到 Finder 槽位，并独占进程内复用的图像缓存。
final class FinderMenuIconRenderer {
    /// Finder 菜单图标使用的系统菜单字体。
    private static let menuIconFont = NSFont.menuFont(ofSize: 0)

    /// SF Symbol 相对菜单字体使用的统一系统比例。
    private static let systemSymbolScale: NSImage.SymbolScale = .small

    /// 菜单字体完整行盒向上取整后的正方形画布边长。
    ///
    /// Finder host 会把非正方形 `NSImage` 拉伸到方形槽位，因此所有来源
    /// 都必须先在 Extension 内保持比例地包装为正方形图像。
    private static let menuIconCanvasLength = ceil(
        menuIconFont.ascender
            - menuIconFont.descender
            + menuIconFont.leading
    )

    /// SF Symbol 和应用图标共用的正方形画布。
    private static let menuIconCanvasSize = NSSize(
        width: menuIconCanvasLength,
        height: menuIconCanvasLength
    )

    /// 复用已经居中适配的固定符号和应用图标，避免重复创建图像。
    private var iconCache: [String: NSImage] = [:]

    /// 把共享的无框架图标声明解析为 Finder 可以显示的 AppKit 图像。
    /// - Parameter icon: 当前菜单项的图标声明。
    /// - Returns: SF Symbol、实际应用图标或图标读取失败占位符。
    func image(
        for icon: ContextCommandIcon
    ) -> NSImage? {
        switch icon {
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

            let cacheKey = "application:\(applicationURL.path)"
            if let cachedIcon = iconCache[cacheKey] {
                return cachedIcon
            }

            let sourceIcon = NSWorkspace.shared.icon(
                forFile: applicationURL.path
            )
            guard let icon = AppKitIconCanvasRenderer
                .proportionallyFittedImage(
                    sourceIcon,
                    canvasSize: Self.menuIconCanvasSize
                )
            else {
                return systemSymbol(named: "questionmark.app.dashed")
            }
            iconCache[cacheKey] = icon
            return icon
        }
    }

    /// 创建不会被 Finder 非等比拉伸的 SF Symbol，并按名称缓存。
    /// - Parameter name: SF Symbols 中的稳定符号名称。
    /// - Returns: 当前系统支持该符号时返回保持自然比例和语义对齐的图像。
    private func systemSymbol(named name: String) -> NSImage? {
        let cacheKey = "symbol:\(name)"
        if let cachedIcon = iconCache[cacheKey] {
            return cachedIcon
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: Self.menuIconFont.pointSize,
            weight: .regular,
            scale: Self.systemSymbolScale
        ).applying(
            NSImage.SymbolConfiguration(hierarchicalColor: .labelColor)
        )
        guard let sourceIcon = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration),
            let icon = AppKitIconCanvasRenderer.semanticCenteredSymbol(
                sourceIcon,
                canvasSize: Self.menuIconCanvasSize
            )
        else {
            return nil
        }

        iconCache[cacheKey] = icon
        return icon
    }
}

import AppKit

/// 把状态页图标渲染到统一设置界面画布。
///
/// 所有设置图标共用 `StatusPageStyle` 的字号和画布，以及 Finder
/// 菜单已验证的自然尺寸、语义居中和越界裁切算法。
enum StatusPageIconRenderer {
    /// 状态页导航、设置行与命令预览共用的画布尺寸。
    static let canvasSize = NSSize(
        width: StatusPageStyle.iconCanvasLength,
        height: StatusPageStyle.iconCanvasLength
    )

    /// 渲染一个可跟随 SwiftUI 前景色的单色设置图标。
    /// - Parameter name: SF Symbols 中的稳定符号名称。
    /// - Returns: 语义居中的 template 图像；系统不支持该符号时为 `nil`。
    static func monochromeSystemSymbol(named name: String) -> NSImage? {
        systemSymbol(
            named: name,
            renderingConfiguration: .preferringMonochrome()
        )
    }

    /// 渲染一个使用系统层级明度的分层设置图标。
    /// - Parameters:
    ///   - name: SF Symbols 中的稳定符号名称。
    ///   - hierarchicalColor: 分层渲染使用的基础系统颜色。
    /// - Returns: 保持自然尺寸的方形图像；系统不支持该符号时为 `nil`。
    static func hierarchicalSystemSymbol(
        named name: String,
        hierarchicalColor: NSColor = .labelColor
    ) -> NSImage? {
        systemSymbol(
            named: name,
            renderingConfiguration: NSImage.SymbolConfiguration(
                hierarchicalColor: hierarchicalColor
            )
        )
    }

    /// 将统一字号、字重和 Symbol 比例与具体颜色模式合并后生成源图。
    /// - Parameters:
    ///   - name: SF Symbols 中的稳定符号名称。
    ///   - renderingConfiguration: 单色或分层颜色配置。
    /// - Returns: 语义主体已烘焙到画布中心的图像。
    private static func systemSymbol(
        named name: String,
        renderingConfiguration: NSImage.SymbolConfiguration
    ) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: StatusPageStyle.iconSymbolPointSize,
            weight: .regular,
            scale: .small
        ).applying(renderingConfiguration)
        guard let sourceIcon = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else {
            return nil
        }

        return AppKitIconCanvasRenderer.semanticCenteredSymbol(
            sourceIcon,
            canvasSize: canvasSize
        )
    }

    /// 把应用图标保持比例地居中适配到统一设置图标画布。
    /// - Parameter sourceIcon: Launch Services 返回的应用图标。
    /// - Returns: 不放大、不拉伸的方形图像；源尺寸无效时为 `nil`。
    static func applicationIcon(_ sourceIcon: NSImage) -> NSImage? {
        AppKitIconCanvasRenderer.proportionallyFittedImage(
            sourceIcon,
            canvasSize: canvasSize
        )
    }
}


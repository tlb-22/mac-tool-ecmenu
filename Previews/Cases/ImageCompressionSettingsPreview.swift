import Foundation

/// 集中保存压缩图片设置窗口预览中需要反复手动调整的场景参数。
@MainActor
private enum ImageCompressionSettingsPreviewParameters {
    /// 打开窗口时显示的目标宽度，单位为像素。
    static let maximumWidth = 1_440

    /// 打开窗口时显示的 JPG 质量刻度。
    static let quality = 8

    /// 根据集中参数构造只存在于预览进程内的初始设置。
    static var settings: ImageCompressionSettings {
        ImageCompressionSettings(
            maximumWidth: maximumWidth,
            quality: quality
        )
    }
}

/// 使用生产窗口控制器检查压缩图片设置界面。
@MainActor
enum ImageCompressionSettingsPreview: ApplicationPreview {
    /// `preview-ui.sh` 使用的稳定预览标识。
    static let id = "image-compression-settings"

    /// 注入固定设置和空完成回调，不读取或保存用户偏好。
    static func present() -> AnyObject {
        ImageCompressionSettingsPreviewSession()
    }
}

/// 保活真实设置窗口控制器，不复制表单或窗口布局。
@MainActor
private final class ImageCompressionSettingsPreviewSession {
    /// Preview target 独占的生产设置窗口控制器。
    private let windowController: ImageCompressionSettingsWindowController

    /// 使用集中参数呈现窗口，确认结果仅在当前会话中丢弃。
    init() {
        let windowController = ImageCompressionSettingsWindowController(
            settings: ImageCompressionSettingsPreviewParameters.settings,
            completion: { _ in }
        )
        self.windowController = windowController
        windowController.present()
    }
}

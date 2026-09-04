import AppKit
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
        guard let settings = ImageCompressionSettings(
            maximumWidth: maximumWidth,
            quality: quality
        ) else {
            preconditionFailure("Invalid image compression preview settings")
        }
        return settings
    }
}

/// 使用生产窗口控制器检查压缩图片设置界面。
@MainActor
enum ImageCompressionSettingsPreview: ApplicationPreview {
    /// `preview-ui.sh` 使用的稳定预览标识。
    static let id = "image-compression-settings"

    /// 注入固定设置和空完成回调，不读取或保存用户偏好。
    static func present() -> AnyObject {
        ImageCompressionSettingsPreviewSession(scenario: .normal)
    }
}

/// 使用真实确认操作检查压缩设置的内联验证错误。
@MainActor
enum ImageCompressionSettingsValidationErrorPreview: ApplicationPreview {
    /// `preview-ui.sh` 使用的稳定预览标识。
    static let id = "image-compression-settings-validation-error"

    /// 清空真实输入框并执行生产确认逻辑，不直接修改错误标签。
    static func present() -> AnyObject {
        ImageCompressionSettingsPreviewSession(scenario: .validationError)
    }
}

/// 压缩设置窗口可以直接复现的确定状态。
private enum ImageCompressionSettingsPreviewScenario {
    case normal
    case validationError
}

/// 保活真实设置窗口控制器，不复制表单或窗口布局。
@MainActor
private final class ImageCompressionSettingsPreviewSession {
    /// Preview target 独占的生产设置窗口控制器。
    private let windowController: ImageCompressionSettingsWindowController

    /// 使用集中参数呈现窗口，确认结果仅在当前会话中丢弃。
    init(scenario: ImageCompressionSettingsPreviewScenario) {
        let windowController = ImageCompressionSettingsWindowController(
            settings: ImageCompressionSettingsPreviewParameters.settings,
            completion: { _ in }
        )
        self.windowController = windowController
        switch scenario {
        case .normal:
            windowController.present()
        case .validationError:
            presentValidationError(in: windowController)
        }
    }

    /// 清空生产输入框，再通过真实按钮触发原有验证流程。
    private func presentValidationError(
        in windowController: ImageCompressionSettingsWindowController
    ) {
        guard
            let window = windowController.window,
            let maximumWidthField = window.initialFirstResponder
                as? NSTextField,
            let confirmButton = descendant(
                of: NSButton.self,
                in: window.contentView,
                matching: {
                    $0.identifier
                        == ImageCompressionSettingsControlIdentifier
                            .confirmButton
                }
            )
        else {
            preconditionFailure(
                "Image compression preview controls do not match production"
            )
        }

        maximumWidthField.stringValue = ""
        windowController.present()
        confirmButton.performClick(nil)
    }

    /// 深度优先查找具有稳定生产身份的窗口控件。
    private func descendant<View: NSView>(
        of type: View.Type,
        in root: NSView?,
        matching predicate: (View) -> Bool
    ) -> View? {
        guard let root else {
            return nil
        }
        if let view = root as? View, predicate(view) {
            return view
        }
        for subview in root.subviews {
            if let match = descendant(
                of: type,
                in: subview,
                matching: predicate
            ) {
                return match
            }
        }
        return nil
    }
}

/**
 构建压缩参数窗口、说明文案和确认取消按钮，并集中定义其布局与控件标识。
 验证表单输入后回传用户决定，由交互协调者管理请求生命周期。
 */

import AppKit
import Foundation

/// 测试与辅助技术识别设置窗口控件时使用的稳定身份。
enum ImageCompressionSettingsControlIdentifier {
    static let confirmButton = NSUserInterfaceItemIdentifier(
        "image-compression-confirm"
    )
    static let validationLabel = NSUserInterfaceItemIdentifier(
        "image-compression-validation"
    )
}

// MARK: - ==================== 窗口布局 ====================

/// 保存不能从系统控件固有尺寸直接推导的窗口布局偏好。
@MainActor
enum ImageCompressionSettingsWindowLayout {
    /// 为文本框和质量滑块提供合理操作长度；窗口高度自动拟合内容。
    static let preferredContentWidth: CGFloat = 400

    /// 内容到窗口左右边缘的间距。
    static let contentHorizontalPadding: CGFloat = 24

    /// 内容到窗口上下边缘的间距。
    static let contentVerticalPadding: CGFloat = 24

    /// 两行表单之间的视觉间距。
    static let formRowSpacing: CGFloat = 20

    /// JPG 质量行所在表单到底部分割线的距离。
    static let formToSeparatorSpacing: CGFloat = 20

    /// 分割线到底部错误信息和操作按钮行的距离。
    static let separatorToFooterSpacing: CGFloat = 20

    /// 目标宽度输入框的固定宽度。
    static let maximumWidthFieldWidth: CGFloat = 80
}

// MARK: - ==================== 窗口与表单 ====================

/// 管理一个非模态标准设置窗口的控件、验证和完成回调。
///
/// 主流程由参数协调器提供本次初始设置；
/// 开发预览 target 可直接注入确定设置，不访问存储。
@MainActor
final class ImageCompressionSettingsWindowController:
    NSWindowController,
    NSWindowDelegate
{
    /// 控制器初始化后始终存在、由本对象明确保活的设置窗口。
    private let ownedWindow: NSWindow

    /// 负责参数输入和局部验证的表单。
    private let formView: ImageCompressionSettingsFormView

    /// 在当前窗口内显示最大宽度验证信息。
    private let validationLabel: NSTextField

    /// 窗口只允许调用一次的异步完成出口。
    private var completion: ((ImageCompressionSettings?) -> Void)?

    /// 使用标准标题栏窗口承载本批次设置。
    init(
        settings: ImageCompressionSettings,
        completion: @escaping (ImageCompressionSettings?) -> Void
    ) {
        formView = ImageCompressionSettingsFormView(settings: settings)
        validationLabel = NSTextField(
            labelWithString: String(
                localized: "imageCompression.validation.targetWidth",
                defaultValue: "Enter a positive integer.",
                comment: "Validation message shown below the compression form"
            )
        )
        self.completion = completion

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width:
                    ImageCompressionSettingsWindowLayout.preferredContentWidth,
                height: .zero
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: CompressImagesCommand.descriptor.title)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        ownedWindow = window
        super.init(window: window)
        window.delegate = self
        configureContent()
    }

    /// 不支持从归档恢复窗口控制器。
    required init?(coder: NSCoder) {
        nil
    }

    /// 显示非模态窗口并让最大宽度成为初始输入焦点。
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        ownedWindow.center()
        ownedWindow.makeKeyAndOrderFront(nil)
        formView.focusMaximumWidth()
    }

    /// 点击标题栏关闭按钮等同于取消本次压缩。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(with: nil, closeWindow: false)
        return true
    }

    /// 调用方 Task 取消时关闭对应窗口并恢复等待者。
    func dismiss() {
        finish(with: nil, closeWindow: true)
    }

    /// 构造参数表单、分割线及验证信息与按钮同排的底部操作区。
    private func configureContent() {
        let contentView = NSView()
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(
            ofSize: NSFont.smallSystemFontSize
        )
        validationLabel.identifier =
            ImageCompressionSettingsControlIdentifier.validationLabel
        validationLabel.alignment = .left
        validationLabel.lineBreakMode = .byTruncatingTail
        validationLabel.isHidden = true

        let cancelButton = NSButton(
            title: String(
                localized: "common.cancel",
                defaultValue: "Cancel",
                comment: "Button that cancels the current operation"
            ),
            target: self,
            action: #selector(cancel(_:))
        )
        cancelButton.keyEquivalent = "\u{1b}"

        let compressButton = NSButton(
            title: String(
                localized: "imageCompression.action.compress",
                defaultValue: "Compress",
                comment: "Button that starts image compression"
            ),
            target: self,
            action: #selector(confirm(_:))
        )
        compressButton.identifier =
            ImageCompressionSettingsControlIdentifier.confirmButton
        compressButton.keyEquivalent = "\r"

        let buttonStack = NSStackView(
            views: [cancelButton, compressButton]
        )
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY

        let separator = NSBox()
        separator.boxType = .separator

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footerStack = NSStackView(
            views: [validationLabel, footerSpacer, buttonStack]
        )
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        validationLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let contentStack = NSStackView(
            views: [formView, separator, footerStack]
        )
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.distribution = .fill
        contentStack.setCustomSpacing(
            ImageCompressionSettingsWindowLayout.formToSeparatorSpacing,
            after: formView
        )
        contentStack.setCustomSpacing(
            ImageCompressionSettingsWindowLayout.separatorToFooterSpacing,
            after: separator
        )

        ownedWindow.contentView = contentView
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: ImageCompressionSettingsWindowLayout.contentVerticalPadding
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: ImageCompressionSettingsWindowLayout.contentHorizontalPadding
            ),
            contentView.trailingAnchor.constraint(
                equalTo: contentStack.trailingAnchor,
                constant: ImageCompressionSettingsWindowLayout.contentHorizontalPadding
            ),
            contentView.bottomAnchor.constraint(
                equalTo: contentStack.bottomAnchor,
                constant: ImageCompressionSettingsWindowLayout.contentVerticalPadding
            ),
            cancelButton.widthAnchor.constraint(equalTo: compressButton.widthAnchor),
        ])

        ownedWindow.initialFirstResponder = formView.maximumWidthField
        contentView.layoutSubtreeIfNeeded()
        ownedWindow.setContentSize(
            NSSize(
                width:
                    ImageCompressionSettingsWindowLayout.preferredContentWidth,
                height: contentView.fittingSize.height
            )
        )
    }

    /// 取消当前窗口并结束等待中的命令。
    @objc private func cancel(_ sender: NSButton) {
        finish(with: nil, closeWindow: true)
    }

    /// 验证设置；有效时冻结结果，无效时在原窗口内提示。
    @objc private func confirm(_ sender: NSButton) {
        guard let settings = formView.settings else {
            validationLabel.isHidden = false
            formView.focusMaximumWidth()
            NSSound.beep()
            return
        }

        finish(with: settings, closeWindow: true)
    }

    /// 恢复一次异步请求，并按触发来源选择是否主动关闭窗口。
    private func finish(
        with settings: ImageCompressionSettings?,
        closeWindow: Bool
    ) {
        guard let completion else {
            return
        }
        self.completion = nil

        if closeWindow {
            ownedWindow.close()
        }
        completion(settings)
    }
}

import AppKit
import Foundation

/// 测试与辅助技术识别设置窗口控件时使用的稳定身份。
enum ImageCompressionSettingsControlIdentifier {
    static let confirmButton = NSUserInterfaceItemIdentifier(
        "image-compression-confirm"
    )
}

// MARK: - ==================== 窗口布局 ====================

/// 保存不能从系统控件固有尺寸直接推导的窗口布局偏好。
@MainActor
private enum ImageCompressionSettingsWindowLayout {
    /// 为文本框和质量滑块提供合理操作长度；窗口高度自动拟合内容。
    static let preferredContentWidth: CGFloat = 400

    /// 窗口四边采用的系统标准间距倍数。
    static let contentPaddingMultiplier: CGFloat = 1.2

    /// 两行表单之间的视觉间距。
    static let formRowSpacing: CGFloat = 20

    /// JPG 质量行所在表单到底部分割线的距离。
    static let formToSeparatorSpacing: CGFloat = 20

    /// 分割线到底部错误信息和操作按钮行的距离。
    static let separatorToFooterSpacing: CGFloat = 20

    /// 目标宽度输入框的固定宽度。
    static let maximumWidthFieldWidth: CGFloat = 80
}

// MARK: - ==================== 输入格式化 ====================

/// 使用系统数字格式化能力，并在编辑阶段只接受正整数。
final class PositiveIntegerFormatter: Formatter {
    /// 负责最终数值显示的系统格式化器。
    private let numberFormatter: NumberFormatter

    /// 构造不使用小数和分组符号的正整数格式化器。
    override init() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: ImageCompressionWidthRules.minimum)
        formatter.usesGroupingSeparator = false
        formatter.isLenient = false
        numberFormatter = formatter
        super.init()
    }

    /// 不支持从归档恢复格式化器。
    required init?(coder: NSCoder) {
        nil
    }

    /// 使用系统数字格式化器生成字段显示文本。
    override func string(for obj: Any?) -> String? {
        numberFormatter.string(for: obj)
    }

    /// 在提交时把有效正整数转换为 `NSNumber`。
    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard let value = Self.positiveInteger(from: string) else {
            error?.pointee = String(
                localized: "imageCompression.validation.positiveInteger",
                defaultValue: "Enter a positive integer.",
                comment: "Input validation message for the target-width field"
            ) as NSString
            return false
        }

        obj?.pointee = NSNumber(value: value)
        return true
    }

    /// 允许暂时清空字段，其他中间输入必须已经是有效正整数。
    override func isPartialStringValid(
        _ partialString: String,
        newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard !partialString.isEmpty else {
            return true
        }
        guard Self.positiveInteger(from: partialString) != nil else {
            error?.pointee = String(
                localized: "imageCompression.validation.positiveInteger",
                defaultValue: "Enter a positive integer.",
                comment: "Input validation message for the target-width field"
            ) as NSString
            return false
        }
        return true
    }

    /// 解析只由十进制数字组成且未发生 `Int` 溢出的正整数。
    private static func positiveInteger(from string: String) -> Int? {
        guard
            !string.isEmpty,
            string.rangeOfCharacter(
                from: CharacterSet.decimalDigits.inverted
            ) == nil,
            let value = Int(string),
            ImageCompressionWidthRules.validated(value) != nil
        else {
            return nil
        }
        return value
    }
}

// MARK: - ==================== 设置窗口入口 ====================

/// 显示独立的标准 macOS 压缩设置窗口。
@MainActor
enum ImageCompressionSettingsPrompt {
    /// 主应用使用的压缩设置持久化边界。
    private static let settingsStore = ImageCompressionSettingsStore()

    /// 保活尚未确认或取消的独立设置窗口，不承载批次目标或业务状态。
    private static var activeControllers: [
        UUID: ImageCompressionSettingsWindowController
    ] = [:]

    /// 异步请求本批次设置，不使用应用级模态循环阻塞其他命令。
    ///
    /// 取消、关闭窗口或取消调用方 Task 都返回 `nil`，且不修改持久化值。
    static func request() async -> ImageCompressionSettings? {
        await request(settingsStore: settingsStore) { controller in
            controller.present()
        }
    }

    /// 使用明确的设置存储和呈现出口请求设置。
    static func request(
        settingsStore: ImageCompressionSettingsStore,
        present: (ImageCompressionSettingsWindowController) -> Void
    ) async -> ImageCompressionSettings? {
        let promptID = UUID()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                let controller = ImageCompressionSettingsWindowController(
                    settings: settingsStore.load()
                ) { settings in
                    activeControllers[promptID] = nil
                    if let settings {
                        settingsStore.save(settings)
                    }
                    continuation.resume(returning: settings)
                }
                activeControllers[promptID] = controller
                present(controller)
            }
        } onCancel: {
            Task { @MainActor in
                activeControllers[promptID]?.dismiss()
            }
        }
    }
}

// MARK: - ==================== 窗口与表单 ====================

/// 管理一个非模态标准设置窗口的控件、验证和完成回调。
///
/// 主流程可通过 `ImageCompressionSettingsPrompt` 使用持久化设置；
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

    /// 构造参数表单、分割线和单行底部操作区。
    private func configureContent() {
        let contentView = NSView()
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(
            ofSize: NSFont.smallSystemFontSize
        )
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
        let contentPaddingMultiplier =
            ImageCompressionSettingsWindowLayout.contentPaddingMultiplier

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(
                equalToSystemSpacingBelow: contentView.topAnchor,
                multiplier: contentPaddingMultiplier
            ),
            contentStack.leadingAnchor.constraint(
                equalToSystemSpacingAfter: contentView.leadingAnchor,
                multiplier: contentPaddingMultiplier
            ),
            contentView.trailingAnchor.constraint(
                equalToSystemSpacingAfter: contentStack.trailingAnchor,
                multiplier: contentPaddingMultiplier
            ),
            contentView.bottomAnchor.constraint(
                equalToSystemSpacingBelow: contentStack.bottomAnchor,
                multiplier: contentPaddingMultiplier
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

/// 高内聚地管理最大宽度字段、质量滑块和当前质量值。
@MainActor
private final class ImageCompressionSettingsFormView: NSView {
    /// 用户编辑最大宽度的整数文本框。
    let maximumWidthField: NSTextField

    /// 只允许 `0...10` 整数刻度的质量滑块。
    private let qualitySlider: NSSlider

    /// 实时显示当前整数质量的文本标签。
    private let qualityValueLabel: NSTextField

    /// 从两个控件读取并验证当前设置。
    var settings: ImageCompressionSettings? {
        guard let maximumWidth = Int(maximumWidthField.stringValue) else {
            return nil
        }
        return ImageCompressionSettings(
            maximumWidth: maximumWidth,
            quality: Int(qualitySlider.doubleValue.rounded())
        )
    }

    /// 使用最后确认的设置构造可随窗口宽度伸缩的原生表单。
    init(settings: ImageCompressionSettings) {
        maximumWidthField = NSTextField(
            string: String(settings.maximumWidth)
        )
        qualitySlider = NSSlider(
            value: Double(settings.quality),
            minValue: Double(ImageCompressionQualityScale.minimum),
            maxValue: Double(ImageCompressionQualityScale.maximum),
            target: nil,
            action: nil
        )
        qualityValueLabel = NSTextField(
            labelWithString: String(settings.quality)
        )
        super.init(frame: .zero)

        let qualityValueWidth = ImageCompressionQualityScale.validValues.reduce(
            CGFloat.zero
        ) { widestWidth, value in
            qualityValueLabel.stringValue = String(value)
            return max(widestWidth, qualityValueLabel.intrinsicContentSize.width)
        }
        qualityValueLabel.stringValue = String(settings.quality)
        maximumWidthField.alignment = .left
        maximumWidthField.formatter = PositiveIntegerFormatter()

        let maximumWidthLabel = NSTextField(
            labelWithString: String(
                localized: "imageCompression.field.targetWidth",
                defaultValue: "Target Width:",
                comment: "Label for the target-width input field"
            )
        )

        let qualityLabel = NSTextField(
            labelWithString: String(
                localized: "imageCompression.field.jpgQuality",
                defaultValue: "JPG Quality:",
                comment: "Label for the JPG quality slider"
            )
        )
        qualitySlider.numberOfTickMarks = ImageCompressionQualityScale.tickCount
        qualitySlider.allowsTickMarkValuesOnly = true
        qualitySlider.target = self
        qualitySlider.action = #selector(updateQualityLabel(_:))
        qualityValueLabel.alignment = .right

        let qualityControls = NSStackView(
            views: [qualitySlider, qualityValueLabel]
        )
        qualityControls.orientation = .horizontal
        qualityControls.alignment = .centerY
        qualityControls.setContentHuggingPriority(.defaultLow, for: .horizontal)
        qualitySlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let maximumWidthUnitLabel = NSTextField(
            labelWithString: String(
                localized: "imageCompression.unit.pixels",
                defaultValue: "pixels",
                comment: "Unit shown after the target-width value"
            )
        )
        let maximumWidthSpacer = NSView()
        maximumWidthSpacer.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )
        let maximumWidthControls = NSStackView(
            views: [
                maximumWidthField,
                maximumWidthUnitLabel,
                maximumWidthSpacer,
            ]
        )
        maximumWidthControls.orientation = .horizontal
        maximumWidthControls.alignment = .centerY

        let grid = NSGridView(
            views: [
                [maximumWidthLabel, maximumWidthControls],
                [qualityLabel, qualityControls],
            ]
        )
        grid.rowSpacing = ImageCompressionSettingsWindowLayout.formRowSpacing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor),
            maximumWidthField.widthAnchor.constraint(
                equalToConstant:
                    ImageCompressionSettingsWindowLayout.maximumWidthFieldWidth
            ),
            qualityValueLabel.widthAnchor.constraint(
                equalToConstant: qualityValueWidth
            ),
        ])
    }

    /// 不支持从归档恢复设置视图。
    required init?(coder: NSCoder) {
        nil
    }

    /// 让无效宽度字段成为第一响应者并选中全文。
    func focusMaximumWidth() {
        window?.makeFirstResponder(maximumWidthField)
        maximumWidthField.selectText(nil)
    }

    /// 滑动时立即显示已经吸附到刻度的整数质量。
    @objc private func updateQualityLabel(_ sender: NSSlider) {
        qualityValueLabel.stringValue = String(
            Int(sender.doubleValue.rounded())
        )
    }
}

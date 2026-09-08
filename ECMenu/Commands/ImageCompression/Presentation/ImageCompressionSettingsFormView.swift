/**
 构建最大宽度字段、质量滑块与实时数值标签组成的原生压缩表单。
 从当前控件内容读取有效领域设置，并支持定位无效宽度输入。
 */

import AppKit
import Foundation

/// 高内聚地管理最大宽度字段、质量滑块和当前质量值。
@MainActor
final class ImageCompressionSettingsFormView: NSView {
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

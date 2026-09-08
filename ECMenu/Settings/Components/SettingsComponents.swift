/**
 提供配置页面复用的行、标签、开关与图标等 SwiftUI 组件。
 将统一外观与布局封装为视图构件，业务状态由调用页面提供。
 */

import AppKit
import SwiftUI

/// 设置窗口与能力页面共用的原生行、控件及图标呈现。
enum SettingsComponents {
    /// 使用同一骨架对齐设置标题与尾部控件。
    @ViewBuilder
    static func settingRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: StatusPageStyle.rowSpacing) {
            leading()

            Spacer(minLength: StatusPageStyle.rowSpacing)

            trailing()
        }
        .padding(.horizontal, StatusPageStyle.rowHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: StatusPageStyle.rowHeight)
    }

    /// 使用固定图标槽位构造设置行左侧标签。
    @ViewBuilder
    static func settingLabel<Icon: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: StatusPageStyle.rowSpacing) {
            icon()
            Text(title)
        }
    }

    /// 构造状态页统一使用的小型开关。
    static func compactToggle(
        _ accessibilityTitle: LocalizedStringResource,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(accessibilityTitle, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }

    /// 以自然字号把通用页 SF Symbol 居中放入统一槽位。
    static func systemRowIcon(_ name: String) -> some View {
        monochromeSystemIcon(name)
    }

    /// 使用统一字号、画布和语义居中算法构造单色设置图标。
    @ViewBuilder
    static func monochromeSystemIcon(_ name: String) -> some View {
        if let image = StatusPageIconRenderer.monochromeSystemSymbol(
            named: name
        ) {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(
                    width: StatusPageStyle.iconCanvasLength,
                    height: StatusPageStyle.iconCanvasLength
                )
                .accessibilityHidden(true)
        } else {
            emptyStatusIcon
        }
    }

    /// 把共享图标声明转换为状态页中的图标视图。
    /// - Parameter descriptor: 当前命令声明。
    /// - Returns: SF Symbol、应用图标或应用缺失占位符。
    @ViewBuilder
    static func commandIcon(
        for descriptor: ContextCommandDescriptor,
        systemState: StatusPageSystemState
    ) -> some View {
        switch descriptor.icon {
        case .systemSymbol(let name):
            if let image = StatusPageIconRenderer.hierarchicalSystemSymbol(
                named: name
            ) {
                renderedCommandIcon(image)
            } else {
                emptyStatusIcon
            }

        case .application(let application):
            if
                let sourceImage = systemState.applicationIcons[application.bundleIdentifier],
                let image = StatusPageIconRenderer.applicationIcon(
                    sourceImage
                )
            {
                renderedCommandIcon(image)
            } else if let image = StatusPageIconRenderer.hierarchicalSystemSymbol(
                named: "questionmark.app.dashed",
                hierarchicalColor: .secondaryLabelColor
            ) {
                renderedCommandIcon(image)
            } else {
                emptyStatusIcon
            }
        }
    }

    /// 把已按统一设置算法生成的画布原尺寸放入设置行。
    /// - Parameter image: 固定行高画布上的 Symbol 或应用图标。
    /// - Returns: 不再缩放且不单独参与辅助功能语义的图标视图。
    static func renderedCommandIcon(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .frame(
                width: StatusPageStyle.iconCanvasLength,
                height: StatusPageStyle.iconCanvasLength
            )
            .accessibilityHidden(true)
    }

    /// 系统缺失声明符号时仍保留标题的统一起点。
    static var emptyStatusIcon: some View {
        Color.clear
            .frame(
                width: StatusPageStyle.iconCanvasLength,
                height: StatusPageStyle.iconCanvasLength
            )
            .accessibilityHidden(true)
    }
}

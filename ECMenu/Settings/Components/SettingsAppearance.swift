/**
 集中定义配置窗口共享的视觉参数与本地化辅助功能文案。
 为设置页壳和各业务页面提供一致的呈现约束。
 */

import AppKit
import SwiftUI

/// 集中保存跨区域复用、会共同影响状态页风格的关键参数。
enum StatusPageStyle {
    /// 左侧导航栏的固定宽度。
    static let sidebarWidth: CGFloat = 180

    /// 右侧设置内容的固定宽度。
    static let detailWidth: CGFloat = 480

    /// 整个页面的固定高度。
    static let pageHeight: CGFloat = 400

    /// 页面主要内容区共用的外边距。
    static let contentPadding: CGFloat = 24

    /// 两组设置之间的垂直间距。
    static let sectionSpacing: CGFloat = 16

    /// 设置行的最小高度。
    static let rowHeight: CGFloat = 36

    /// 行内图标、标题和尾部控件共用的间距。
    static let rowSpacing: CGFloat = 8

    /// 所有设置图标共用的正方形画布边长。
    static let iconCanvasLength: CGFloat = 20

    /// 所有设置 SF Symbol 共用的光学字号。
    static let iconSymbolPointSize: CGFloat = 16

    /// 设置行内容与容器左右边缘之间的空白。
    static let rowHorizontalPadding: CGFloat = 8

    /// 状态页顶部产品图标的正方形槽位边长。
    static let appIconFrameSize: CGFloat = 50
}

/// 没有独立视觉文字的状态与按钮的本地化辅助功能语义。
enum StatusPageAccessibility {
    static func showCommand(_ title: LocalizedStringResource) -> LocalizedStringResource {
        LocalizedStringResource(
            "statusPage.contextMenu.showCommand",
            defaultValue: "Show \(title)",
            comment: "Accessibility label for a switch that shows a command in Finder"
        )
    }

    static let extensionSettings = LocalizedStringResource(
        "statusPage.accessibility.extensionSettings",
        defaultValue: "Open Finder Extension settings",
        comment: "Accessibility label for the Finder Extension settings button"
    )
    static let fullDiskAccessSettings = LocalizedStringResource(
        "statusPage.accessibility.fullDiskAccessSettings",
        defaultValue: "Open Full Disk Access settings",
        comment: "Accessibility label for the Full Disk Access settings button"
    )

    static func extensionState(isEnabled: Bool) -> LocalizedStringResource {
        isEnabled
            ? LocalizedStringResource(
                "statusPage.accessibility.extensionEnabled",
                defaultValue: "Enabled",
                comment: "Accessibility value of an enabled Finder Extension"
            )
            : LocalizedStringResource(
                "statusPage.accessibility.extensionDisabled",
                defaultValue: "Disabled",
                comment: "Accessibility value of a disabled Finder Extension"
            )
    }
}


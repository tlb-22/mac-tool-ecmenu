/**
 集中定义进度窗口与任务行使用的布局参数。
 为原生展示组件提供一致的尺寸、间距和窗口约束。
 */

import AppKit
import Foundation

/// 保存共享进度窗口中不可从系统控件推导的布局偏好。
@MainActor
enum ContextCommandProgressWindowLayout {
    /// 官方 Finder 任务窗口风格的紧凑固定宽度。
    static let contentWidth: CGFloat = 400

    /// 任务内容到窗口左右边缘的留白。
    static let windowHorizontalPadding: CGFloat = 12

    /// 任务内容到窗口上下边缘的留白。
    static let windowVerticalPadding: CGFloat = 8

    /// 多个并发任务行之间的间距。
    static let taskSpacing: CGFloat = 12

    /// 图标固定画布的边长。
    static let iconCanvasLength: CGFloat = 40

    /// 图标与右侧三行任务信息之间的间距。
    static let iconContentSpacing: CGFloat = 10

    /// 标题、进度控件和计数三行之间的间距。
    static let detailRowSpacing: CGFloat = 4

    /// 右侧上方命令名称的字体大小。
    static let titleFontSize: CGFloat = 11

    /// 右侧下方完成数量的字体大小。
    static let countFontSize: CGFloat = 11

    /// 进度条与取消按钮之间的间距。
    static let progressControlSpacing: CGFloat = 8

    /// 取消按钮内部叉号 SF Symbol 的可见字号。
    static let cancelButtonSymbolPointSize: CGFloat = 14

    /// Finder 风格按钮让点击区域与圆叉的配置尺寸基本重合。
    static var cancelButtonLength: CGFloat {
        cancelButtonSymbolPointSize
    }

    /// Finder 风格确定进度槽的可见高度。
    static let progressBarHeight: CGFloat = 8
}

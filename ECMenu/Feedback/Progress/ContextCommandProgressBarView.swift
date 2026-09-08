/**
 根据完成数量绘制原生进度条，并同步辅助功能数值。
 观察所属窗口焦点与外观以更新颜色，业务进度由运行时传入。
 */

import AppKit
import Foundation

/// 按 nonactivating 面板的焦点状态绘制确定进度槽。
@MainActor
final class ContextCommandProgressBarView: NSView {
    /// 当前已经完成的比例，始终限制在 `0...1`。
    private var completedFraction: CGFloat = 0

    /// 当前为进度槽提供 key 状态的窗口。
    private weak var observedWindow: NSWindow?

    /// 进度槽只声明高度，横向由任务行约束自适应填满。
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: ContextCommandProgressWindowLayout.progressBarHeight
        )
    }

    /// 创建可由 VoiceOver 读取的确定进度元素。
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(1)
        setAccessibilityValue(0)
    }

    /// 不支持从归档恢复进度槽。
    required init?(coder: NSCoder) {
        nil
    }

    /// 释放时移除仍可能绑定在窗口上的焦点通知。
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 只观察当前所属窗口的 key 状态变化，并据此刷新填充颜色。
    override func viewDidMoveToWindow() {
        if let observedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didBecomeKeyNotification,
                object: observedWindow
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: observedWindow
            )
        }

        super.viewDidMoveToWindow()
        observedWindow = window

        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFocusDidChange(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowFocusDidChange(_:)),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
        }
        needsDisplay = true
    }

    /// 更新确定进度，并同步可访问值与显示。
    func apply(completedUnitCount: Int, totalUnitCount: Int) {
        let nextFraction = CGFloat(completedUnitCount) / CGFloat(totalUnitCount)

        guard nextFraction != completedFraction else {
            return
        }
        completedFraction = nextFraction
        setAccessibilityValue(nextFraction)
        needsDisplay = true
    }

    /// 绘制自适应圆角轨道，并按 key window 状态选择填充颜色。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let trackRadius = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: trackRadius,
            yRadius: trackRadius
        ).fill()

        let completedWidth = bounds.width * completedFraction
        guard completedWidth > 0 else {
            return
        }

        let completedRect = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: completedWidth,
            height: bounds.height
        )
        let completedRadius = min(trackRadius, completedWidth / 2)
        let completedColor: NSColor = window?.isKeyWindow == true
            ? .controlAccentColor
            : .secondaryLabelColor
        completedColor.setFill()
        NSBezierPath(
            roundedRect: completedRect,
            xRadius: completedRadius,
            yRadius: completedRadius
        ).fill()
    }

    /// 深浅外观变化后重新解析系统动态颜色。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// 窗口获得或失去焦点时重绘动态颜色，不改变进度数值。
    @objc private func windowFocusDidChange(_ notification: Notification) {
        needsDisplay = true
    }
}

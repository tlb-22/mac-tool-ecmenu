/**
 持有进度窗口及任务行，协调列表更新、窗口显示与关闭回调。
 根据状态快照维护原生控件身份，业务进度和取消状态由运行时管理。
 */

import AppKit
import Foundation

/// 管理一个不激活主应用、可以同时展示多项任务的标准 AppKit 面板。
@MainActor
final class ContextCommandProgressWindowController:
    NSWindowController,
    NSWindowDelegate
{
    /// 用户点击某一任务取消按钮时的唯一动作出口。
    private let cancelAction: (UUID) -> Void

    /// 用户关闭窗口时冻结当前呈现任务的动作出口。
    private let dismissAction: () -> Void

    /// 按开始顺序排列任务行的自适应容器。
    private let taskStack = NSStackView()

    /// 把共享 descriptor 的图标声明解析为 AppKit 图像。
    private let iconResolver = ContextCommandProgressIconResolver()

    /// 使用请求身份复用现有行，进度更新不会反复重建控件。
    private var rowViews: [UUID: ContextCommandProgressRowView] = [:]

    /// 创建不抢占 Finder 焦点的共享非模态任务面板。
    init(
        cancelAction: @escaping (UUID) -> Void,
        dismissAction: @escaping () -> Void
    ) {
        self.cancelAction = cancelAction
        self.dismissAction = dismissAction

        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ContextCommandProgressWindowLayout.contentWidth,
                height: 0
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        panel.title = ApplicationMetadata.displayName
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // 自动出现时仍不激活应用；用户主动点击后允许面板成为 key window。
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel.standardWindowButton(.closeButton)?.isEnabled = true
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        panel.standardWindowButton(.zoomButton)?.isEnabled = false

        super.init(window: panel)
        panel.delegate = self
        configureContent(of: panel)
    }

    /// 不支持从归档恢复窗口控制器。
    required init?(coder: NSCoder) {
        nil
    }

    /// 复用任务行并按照状态顺序更新共享窗口。
    func update(with items: [ContextCommandProgressItem]) {
        let activeIDs = Set(items.map(\.requestID))
        let staleRequestIDs = rowViews.keys.filter {
            !activeIDs.contains($0)
        }
        for requestID in staleRequestIDs {
            guard let rowView = rowViews[requestID] else {
                continue
            }
            taskStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
            rowViews[requestID] = nil
        }

        for (desiredIndex, item) in items.enumerated() {
            let rowView: ContextCommandProgressRowView
            if let existing = rowViews[item.requestID] {
                rowView = existing
            } else {
                rowView = ContextCommandProgressRowView(
                    requestID: item.requestID,
                    iconResolver: iconResolver,
                    cancelAction: cancelAction
                )
                rowViews[item.requestID] = rowView
            }
            rowView.apply(item)
            place(rowView, at: desiredIndex)
            rowView.fillWidth(of: taskStack)
        }

        resizeToFitContent()
        window?.orderFrontRegardless()
    }

    /// 最后一个任务结束后关闭面板并恢复下一批的显示状态。
    func closeWhenEmpty() {
        rowViews.removeAll()
        for view in taskStack.arrangedSubviews {
            taskStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        close()
    }

    /// 用户关闭面板只隐藏当前批次，不取消任何文件操作。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismissAction()
        return true
    }

    /// 只有新增或真实顺序变化时才调整 arranged subview 层级。
    private func place(
        _ rowView: ContextCommandProgressRowView,
        at desiredIndex: Int
    ) {
        let arrangedSubviews = taskStack.arrangedSubviews
        if
            arrangedSubviews.indices.contains(desiredIndex),
            arrangedSubviews[desiredIndex] === rowView
        {
            return
        }

        if arrangedSubviews.contains(where: { $0 === rowView }) {
            taskStack.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }
        taskStack.insertArrangedSubview(
            rowView,
            at: min(desiredIndex, taskStack.arrangedSubviews.count)
        )
    }

    /// 构造使用集中布局参数约束的多任务内容容器。
    private func configureContent(of panel: NSPanel) {
        let contentView = NSView()
        taskStack.orientation = .vertical
        taskStack.alignment = .leading
        taskStack.distribution = .fill
        taskStack.spacing = ContextCommandProgressWindowLayout.taskSpacing
        taskStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(taskStack)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            taskStack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: ContextCommandProgressWindowLayout.windowVerticalPadding
            ),
            taskStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: ContextCommandProgressWindowLayout.windowHorizontalPadding
            ),
            contentView.trailingAnchor.constraint(
                equalTo: taskStack.trailingAnchor,
                constant: ContextCommandProgressWindowLayout.windowHorizontalPadding
            ),
            contentView.bottomAnchor.constraint(
                equalTo: taskStack.bottomAnchor,
                constant: ContextCommandProgressWindowLayout.windowVerticalPadding
            ),
            contentView.widthAnchor.constraint(
                equalToConstant: ContextCommandProgressWindowLayout.contentWidth
            ),
        ])
    }

    /// 保留窗口顶部位置，让并发任务加入时向下自然增长。
    private func resizeToFitContent() {
        guard let window, let contentView = window.contentView else {
            return
        }
        contentView.layoutSubtreeIfNeeded()
        let previousTop = window.frame.maxY
        window.setContentSize(
            NSSize(
                width: ContextCommandProgressWindowLayout.contentWidth,
                height: contentView.fittingSize.height
            )
        )

        if window.isVisible {
            window.setFrameOrigin(
                NSPoint(x: window.frame.minX, y: previousTop - window.frame.height)
            )
        } else {
            window.center()
        }
    }
}

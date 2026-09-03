import AppKit
import Foundation

// MARK: - ==================== Finder 风格共享任务窗口 ====================

/// 保存共享进度窗口中不可从系统控件推导的布局偏好。
@MainActor
private enum ContextCommandProgressWindowLayout {
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

/// 把共享命令的图标声明解析为统一正方形画布。
@MainActor
private final class ContextCommandProgressIconResolver {
    /// SF Symbol 和应用图标均按稳定来源缓存。
    private var cache: [String: NSImage] = [:]

    /// 解析 descriptor 的真实图标，外部应用缺失时使用统一占位符。
    func image(for descriptor: ContextCommandDescriptor) -> NSImage? {
        switch descriptor.icon {
        case .systemSymbol(let name):
            return systemSymbol(named: name)

        case .application(let requirement):
            guard
                let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: requirement.bundleIdentifier
                )
            else {
                return systemSymbol(named: "questionmark.app.dashed")
            }

            let cacheKey = "application:\(requirement.bundleIdentifier)"
            if let cachedImage = cache[cacheKey] {
                return cachedImage
            }

            let sourceImage = NSWorkspace.shared.icon(
                forFile: applicationURL.path
            )
            guard let image = centeredImage(sourceImage) else {
                return systemSymbol(named: "questionmark.app.dashed")
            }
            cache[cacheKey] = image
            return image
        }
    }

    /// 按系统标签颜色创建 SF Symbol。
    private func systemSymbol(named name: String) -> NSImage? {
        let cacheKey = "symbol:\(name)"
        if let cachedImage = cache[cacheKey] {
            return cachedImage
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 30,
            weight: .regular
        ).applying(
            NSImage.SymbolConfiguration(hierarchicalColor: .labelColor)
        )
        guard
            let sourceImage = NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(configuration),
            let image = centeredImage(sourceImage)
        else {
            return nil
        }

        cache[cacheKey] = image
        return image
    }

    /// 保持比例缩放并居中，非正方形图标不被拉伸或裁切。
    private func centeredImage(_ sourceImage: NSImage) -> NSImage? {
        let sourceSize = sourceImage.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }

        let canvasLength = ContextCommandProgressWindowLayout.iconCanvasLength
        let canvasSize = NSSize(width: canvasLength, height: canvasLength)
        let maximumIconLength = canvasLength - 4
        let scale = min(
            maximumIconLength / sourceSize.width,
            maximumIconLength / sourceSize.height
        )
        let fittedSize = NSSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let fittedRect = NSRect(
            x: (canvasLength - fittedSize.width) / 2,
            y: (canvasLength - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )

        let image = NSImage(size: canvasSize, flipped: false) { _ in
            sourceImage.draw(
                in: fittedRect,
                from: NSRect(origin: .zero, size: sourceSize),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }
        image.isTemplate = sourceImage.isTemplate
        return image
    }
}

/// 按 nonactivating 面板的焦点状态绘制确定进度槽。
@MainActor
private final class ContextCommandProgressBarView: NSView {
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

/// 一项命令的名称、确定进度、计数和可选取消控件。
@MainActor
private final class ContextCommandProgressRowView: NSView {
    /// 当前任务行绑定的稳定请求身份。
    private let requestID: UUID

    /// 在固定正方形画布内居中显示 descriptor 图标。
    private let iconImageView = NSImageView()

    /// 命令产品名称。
    private let titleLabel = NSTextField(labelWithString: "")

    /// Finder 风格的确定进度槽。
    private let progressBar = ContextCommandProgressBarView()

    /// 以“已完成 / 总数”显示的项目计数。
    private let countLabel = NSTextField(labelWithString: "")

    /// 请求 Feature 在下一个安全边界停止的按钮。
    private let cancelButton = NSButton()

    /// 为命令解析 SF Symbol 或所依赖应用图标。
    private let iconResolver: ContextCommandProgressIconResolver

    /// 避免进度数值更新时重复解析未变化的图标。
    private var appliedDescriptor: ContextCommandDescriptor?

    /// 任务行加入共享纵向容器后建立的唯一等宽约束。
    private var stackWidthConstraint: NSLayoutConstraint?

    /// 转发用户取消意图，不直接终止正在写入的一项。
    private let cancelAction: (UUID) -> Void

    /// 绑定请求身份并构造自适应任务行。
    init(
        requestID: UUID,
        iconResolver: ContextCommandProgressIconResolver,
        cancelAction: @escaping (UUID) -> Void
    ) {
        self.requestID = requestID
        self.iconResolver = iconResolver
        self.cancelAction = cancelAction
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureContent()
    }

    /// 不支持从归档恢复任务行。
    required init?(coder: NSCoder) {
        nil
    }

    /// 把不可变进度快照应用到现有系统控件。
    func apply(_ item: ContextCommandProgressItem) {
        if appliedDescriptor != item.descriptor {
            appliedDescriptor = item.descriptor
            let localizedTitle = String(localized: item.descriptor.title)
            titleLabel.stringValue = localizedTitle
            iconImageView.image = iconResolver.image(for: item.descriptor)
            iconImageView.setAccessibilityLabel(localizedTitle)
        }
        progressBar.apply(
            completedUnitCount: item.completedUnitCount,
            totalUnitCount: item.totalUnitCount
        )
        countLabel.stringValue = "\(item.completedUnitCount) / \(item.totalUnitCount)"
        cancelButton.isEnabled = !item.isCancellationRequested
        let cancelToolTip = item.isCancellationRequested
            ? LocalizedStringResource(
                "progress.cancelling",
                defaultValue: "Cancelling…",
                comment: "Tooltip shown after cancellation has been requested"
            )
            : LocalizedStringResource(
                "common.cancel",
                defaultValue: "Cancel",
                comment: "Button that cancels the current operation"
            )
        cancelButton.toolTip = String(localized: cancelToolTip)
    }

    /// 让任务行明确占满共享纵向容器，而不依赖 Stack 的固有尺寸。
    func fillWidth(of stackView: NSStackView) {
        guard stackWidthConstraint == nil else {
            return
        }

        let constraint = widthAnchor.constraint(equalTo: stackView.widthAnchor)
        constraint.isActive = true
        stackWidthConstraint = constraint
    }

    /// 构造左侧图标与右侧“名称—进度—计数”三行布局。
    private func configureContent() {
        iconImageView.imageAlignment = .alignCenter
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.imageFrameStyle = .none
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(
            ofSize: ContextCommandProgressWindowLayout.titleFontSize,
            weight: .semibold
        )
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        progressBar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .monospacedDigitSystemFont(
            ofSize: ContextCommandProgressWindowLayout.countFontSize,
            weight: .regular
        )
        countLabel.alignment = .left
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let cancelImage = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: String(
                localized: "common.cancel",
                defaultValue: "Cancel",
                comment: "Button that cancels the current operation"
            )
        )
        cancelButton.image = cancelImage?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: ContextCommandProgressWindowLayout
                    .cancelButtonSymbolPointSize,
                weight: .regular
            )
        )
        cancelButton.isBordered = false
        cancelButton.bezelStyle = .inline
        cancelButton.contentTintColor = .secondaryLabelColor
        cancelButton.imagePosition = .imageOnly
        cancelButton.imageScaling = .scaleProportionallyDown
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let progressStack = NSStackView(views: [progressBar, cancelButton])
        progressStack.orientation = .horizontal
        progressStack.alignment = .centerY
        progressStack.distribution = .fill
        progressStack.spacing =
            ContextCommandProgressWindowLayout.progressControlSpacing
        progressStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(progressStack)
        addSubview(countLabel)

        let detailSpacing = ContextCommandProgressWindowLayout.detailRowSpacing
        let detailLeading = titleLabel.leadingAnchor.constraint(
            equalTo: iconImageView.trailingAnchor,
            constant: ContextCommandProgressWindowLayout.iconContentSpacing
        )

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(
                equalToConstant: ContextCommandProgressWindowLayout.iconCanvasLength
            ),
            iconImageView.heightAnchor.constraint(
                equalToConstant: ContextCommandProgressWindowLayout.iconCanvasLength
            ),
            cancelButton.widthAnchor.constraint(
                equalToConstant: ContextCommandProgressWindowLayout.cancelButtonLength
            ),
            cancelButton.heightAnchor.constraint(
                equalToConstant: ContextCommandProgressWindowLayout.cancelButtonLength
            ),
            progressBar.heightAnchor.constraint(
                equalToConstant: ContextCommandProgressWindowLayout.progressBarHeight
            ),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            detailLeading,
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressStack.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: detailSpacing
            ),
            progressStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            countLabel.topAnchor.constraint(
                equalTo: progressStack.bottomAnchor,
                constant: detailSpacing
            ),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            countLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// 禁用按钮并把协作取消意图交给共享任务中心。
    @objc private func cancel(_ sender: NSButton) {
        sender.isEnabled = false
        cancelAction(requestID)
    }
}

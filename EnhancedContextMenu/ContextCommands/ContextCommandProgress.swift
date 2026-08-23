import AppKit
import Foundation

// MARK: - ==================== 进度状态 ====================

/// 长时间右键命令在共享任务窗口中的不可变显示事实。
nonisolated struct ContextCommandProgressItem: Equatable, Sendable {
    /// 主应用本地任务标识，也是任务行的稳定身份。
    let requestID: UUID

    /// 名称、图标和外部应用依赖的唯一声明。
    let descriptor: ContextCommandDescriptor

    /// 命令开始时已经确定的总项目数。
    let totalUnitCount: Int

    /// 已经到达成功或失败终态的项目数。
    var completedUnitCount: Int

    /// Feature 是否能够在安全边界响应用户取消。
    let allowsCancellation: Bool

    /// 用户已经请求取消，Feature 尚未结束当前安全边界。
    var isCancellationRequested: Bool

    /// 任务经过显示延迟后才进入窗口，快速任务不会闪现。
    var isVisible: Bool
}

/// 集中维护多个右键命令的进度状态，不包含 AppKit 副作用。
nonisolated struct ContextCommandProgressState: Equatable, Sendable {
    /// 按命令开始顺序保存全部仍在运行的进度任务。
    private(set) var items: [ContextCommandProgressItem] = []

    /// 当前需要呈现在共享窗口中的任务。
    var visibleItems: [ContextCommandProgressItem] {
        items.filter(\.isVisible)
    }

    /// 登记一个刚刚开始实际执行的可选进度任务。
    /// - Parameters:
    ///   - requestID: Router 为本次右键请求分配的稳定身份。
    ///   - descriptor: 对应命令的完整产品描述。
    ///   - totalUnitCount: 已知且大于零的总项目数。
    ///   - allowsCancellation: Feature 是否实现安全取消边界。
    /// - Returns: 成功登记时为 `true`；重复身份或空任务为 `false`。
    @discardableResult
    mutating func begin(
        requestID: UUID,
        descriptor: ContextCommandDescriptor,
        totalUnitCount: Int,
        allowsCancellation: Bool
    ) -> Bool {
        guard
            totalUnitCount > 0,
            !items.contains(where: { $0.requestID == requestID })
        else {
            return false
        }

        items.append(
            ContextCommandProgressItem(
                requestID: requestID,
                descriptor: descriptor,
                totalUnitCount: totalUnitCount,
                completedUnitCount: 0,
                allowsCancellation: allowsCancellation,
                isCancellationRequested: false,
                isVisible: false
            )
        )
        return true
    }

    /// 让仍在运行的任务经过延迟后出现在窗口中。
    mutating func reveal(requestID: UUID) {
        guard let index = index(of: requestID) else {
            return
        }
        items[index].isVisible = true
    }

    /// 把到达终态的项目数累加，并限制在声明的总数内。
    mutating func advance(requestID: UUID, by unitCount: Int = 1) {
        guard unitCount > 0, let index = index(of: requestID) else {
            return
        }
        let remainingUnitCount =
            items[index].totalUnitCount - items[index].completedUnitCount
        items[index].completedUnitCount += min(
            unitCount,
            remainingUnitCount
        )
    }

    /// 记录用户取消意图；不支持取消的 Feature 保持不变。
    mutating func requestCancellation(requestID: UUID) {
        guard
            let index = index(of: requestID),
            items[index].allowsCancellation
        else {
            return
        }
        items[index].isCancellationRequested = true
    }

    /// 查询 Feature 是否应在下一个安全边界停止。
    func isCancellationRequested(for requestID: UUID) -> Bool {
        guard let index = index(of: requestID) else {
            return false
        }
        return items[index].isCancellationRequested
    }

    /// 命令结束后移除对应任务行。
    mutating func finish(requestID: UUID) {
        items.removeAll { $0.requestID == requestID }
    }

    /// 查找稳定请求身份在有序任务列表中的位置。
    private func index(of requestID: UUID) -> Int? {
        items.firstIndex { $0.requestID == requestID }
    }
}

// MARK: - ==================== Feature 进度能力 ====================

/// 一次命令执行可以选择使用的进度与协作取消入口。
@MainActor
final class ContextCommandProgressReporter {
    /// 本次命令对应的共享任务中心。
    private let center: ContextCommandProgressCenter

    /// Router 分配的稳定请求身份。
    private let requestID: UUID

    /// Command 提供的名称、图标和应用依赖。
    private let descriptor: ContextCommandDescriptor

    /// 绑定请求身份、命令描述和共享任务中心。
    init(
        center: ContextCommandProgressCenter,
        requestID: UUID,
        descriptor: ContextCommandDescriptor
    ) {
        self.center = center
        self.requestID = requestID
        self.descriptor = descriptor
    }

    /// 用户确认参数并即将产生真实工作时开始进度。
    /// - Parameters:
    ///   - totalUnitCount: 批次中需要到达终态的项目数。
    ///   - allowsCancellation: Feature 是否在项目边界检查取消意图。
    func begin(totalUnitCount: Int, allowsCancellation: Bool) {
        center.begin(
            requestID: requestID,
            descriptor: descriptor,
            totalUnitCount: totalUnitCount,
            allowsCancellation: allowsCancellation
        )
    }

    /// 一个项目成功或失败后推进一次进度。
    func advance() {
        center.advance(requestID: requestID)
    }

    /// 查询用户是否已经请求在下一个安全边界取消。
    var isCancellationRequested: Bool {
        center.isCancellationRequested(for: requestID)
    }

    /// Invocation 结束时统一清理可能已经登记的进度任务。
    func finish() {
        center.finish(requestID: requestID)
    }
}

/// Handler 执行期间由稳定框架提供的可选能力集合。
nonisolated struct ContextCommandExecutionContext: Sendable {
    /// 只有主动调用 `begin` 的 Feature 才会产生进度界面。
    let progress: ContextCommandProgressReporter
}

// MARK: - ==================== 生命周期与显示延迟 ====================

/// 拥有全部右键命令进度状态、显示延迟和共享任务窗口。
@MainActor
final class ContextCommandProgressCenter {
    /// 主应用全部 Router 共享的唯一任务中心。
    static let shared = ContextCommandProgressCenter()

    /// 快速任务不显示窗口的统一延迟。
    nonisolated static let standardDisplayDelay: Duration = .seconds(1)

    /// 测试可以替换的显示延迟；生产环境使用统一的一秒阈值。
    private let displayDelay: Duration

    /// 测试可以替换的 AppKit 渲染边界；生产环境由窗口控制器呈现。
    private let renderOverride: (([ContextCommandProgressItem]) -> Void)?

    /// 当前仍在运行的纯进度状态。
    private var state = ContextCommandProgressState()

    /// 每个尚未显示任务对应的独立延迟任务。
    private var revealTasks: [UUID: Task<Void, Never>] = [:]

    /// 用户关闭窗口时已经可见的任务；后续新任务不继承隐藏状态。
    private var dismissedRequestIDs: Set<UUID> = []

    /// 最近一次交给渲染边界的快照，避免无可见变化时触碰 AppKit。
    private var lastRenderedItems: [ContextCommandProgressItem] = []

    /// 至少一个任务可见时才创建并保留窗口控制器。
    private var windowController: ContextCommandProgressWindowController?

    /// 创建进度中心，并允许测试替换延迟和渲染副作用。
    /// - Parameters:
    ///   - displayDelay: 任务从开始到可见之间的统一阈值。
    ///   - render: 接收可见快照的测试边界；省略时使用 AppKit 面板。
    init(
        displayDelay: Duration = standardDisplayDelay,
        render: (([ContextCommandProgressItem]) -> Void)? = nil
    ) {
        self.displayDelay = displayDelay
        renderOverride = render
    }

    /// 登记任务并独立安排延迟显示。
    func begin(
        requestID: UUID,
        descriptor: ContextCommandDescriptor,
        totalUnitCount: Int,
        allowsCancellation: Bool
    ) {
        guard state.begin(
            requestID: requestID,
            descriptor: descriptor,
            totalUnitCount: totalUnitCount,
            allowsCancellation: allowsCancellation
        ) else {
            return
        }

        let displayDelay = displayDelay
        revealTasks[requestID] = Task { [weak self] in
            do {
                try await Task.sleep(for: displayDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.reveal(requestID: requestID)
        }
    }

    /// Feature 报告一个项目已经到达终态。
    func advance(requestID: UUID) {
        state.advance(requestID: requestID)
        renderIfNeeded()
    }

    /// 返回用户在任务窗口中登记的协作取消意图。
    func isCancellationRequested(for requestID: UUID) -> Bool {
        state.isCancellationRequested(for: requestID)
    }

    /// 命令完成、失败或被 Router 取消后清理任务与延迟。
    func finish(requestID: UUID) {
        revealTasks.removeValue(forKey: requestID)?.cancel()
        state.finish(requestID: requestID)
        dismissedRequestIDs.remove(requestID)
        renderIfNeeded()
    }

    /// 延迟到期且任务仍在执行时使其进入共享窗口。
    private func reveal(requestID: UUID) {
        revealTasks[requestID] = nil
        state.reveal(requestID: requestID)
        renderIfNeeded()
    }

    /// 从窗口接收取消按钮动作，不直接取消 Router 的结构化 Task。
    func requestCancellation(requestID: UUID) {
        state.requestCancellation(requestID: requestID)
        renderIfNeeded()
    }

    /// 用户关闭窗口时只隐藏当时呈现的任务，后来任务仍可重新显示。
    func dismissVisibleItems() {
        let requestIDs = currentlyPresentedItems.map(\.requestID)
        guard !requestIDs.isEmpty else {
            return
        }

        dismissedRequestIDs.formUnion(requestIDs)

        // 窗口正在响应自己的关闭动作，不从回调内再次调用 close()。
        windowController = nil
        renderIfNeeded()
    }

    /// 排除用户已经主动隐藏、但仍在后台运行的任务。
    private var currentlyPresentedItems: [ContextCommandProgressItem] {
        state.visibleItems.filter {
            !dismissedRequestIDs.contains($0.requestID)
        }
    }

    /// 只在可见快照变化时进入测试或 AppKit 渲染边界。
    private func renderIfNeeded() {
        let visibleItems = currentlyPresentedItems
        guard visibleItems != lastRenderedItems else {
            return
        }
        lastRenderedItems = visibleItems

        if let renderOverride {
            renderOverride(visibleItems)
            return
        }

        guard !visibleItems.isEmpty else {
            windowController?.closeWhenEmpty()
            windowController = nil
            return
        }

        if windowController == nil {
            windowController = ContextCommandProgressWindowController(
                cancelAction: { [weak self] requestID in
                    self?.requestCancellation(requestID: requestID)
                },
                dismissAction: { [weak self] in
                    self?.dismissVisibleItems()
                }
            )
        }
        windowController?.update(with: visibleItems)
    }
}

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
private final class ContextCommandProgressWindowController:
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

        case .requiredApplication:
            guard
                let requirement = descriptor.requiredApplication,
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
        let nextFraction: CGFloat
        if totalUnitCount > 0 {
            nextFraction = min(
                max(CGFloat(completedUnitCount) / CGFloat(totalUnitCount), 0),
                1
            )
        } else {
            nextFraction = 0
        }

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

    /// 只在 Feature 实现安全取消时显示的按钮。
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
            titleLabel.stringValue = item.descriptor.title
            iconImageView.image = iconResolver.image(for: item.descriptor)
            iconImageView.setAccessibilityLabel(item.descriptor.title)
        }
        progressBar.apply(
            completedUnitCount: item.completedUnitCount,
            totalUnitCount: item.totalUnitCount
        )
        countLabel.stringValue = "\(item.completedUnitCount) / \(item.totalUnitCount)"
        cancelButton.isHidden = !item.allowsCancellation
        cancelButton.isEnabled = !item.isCancellationRequested
        cancelButton.toolTip = item.isCancellationRequested ? "正在取消…" : "取消"
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
            accessibilityDescription: "取消"
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

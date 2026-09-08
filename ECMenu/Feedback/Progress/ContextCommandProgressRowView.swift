/**
 构建单个命令任务的图标、名称、进度与取消控件。
 按任务快照更新原生视图，并回传取消操作。
 */

import AppKit
import Foundation

/// 一项命令的名称、确定进度、计数和可选取消控件。
@MainActor
final class ContextCommandProgressRowView: NSView {
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

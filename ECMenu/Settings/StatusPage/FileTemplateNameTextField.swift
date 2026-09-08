import AppKit
import SwiftUI

/// 名称控件保持原生视图身份，由编辑会话批准字段间的焦点交接。
struct FileTemplateNameTextField: NSViewRepresentable {
    let template: FileTemplate
    let field: FileTemplateNameField
    let session: FileTemplateNameEditingSession
    let allowsEditing: () -> Bool
    let save: (String) async throws -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(template: template, field: field, session: session, allowsEditing: allowsEditing, save: save)
    }

    func makeNSView(context: Context) -> FileTemplateNameNativeField {
        context.coordinator.nativeField
    }

    func updateNSView(_ nativeField: FileTemplateNameNativeField, context: Context) {
        let coordinator = context.coordinator
        precondition(coordinator.target == FileTemplateNameTarget(templateID: template.id, field: field))
        coordinator.session = session
        coordinator.allowsEditing = allowsEditing
        coordinator.save = save
        let allowsEditing = allowsEditing()
        if nativeField.isEditable != allowsEditing { nativeField.isEditable = allowsEditing }
        if nativeField.isSelectable != allowsEditing { nativeField.isSelectable = allowsEditing }
        if nativeField.currentEditor() == nil, !session.isEditing(coordinator) {
            let value = field.value(in: template)
            if nativeField.stringValue != value { nativeField.stringValue = value }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: FileTemplateNameNativeField,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
            height: FileTemplatesStyle.nameHeight
        )
    }

    /// NSControl 已占用 target 属性；协调器承担领域身份并适配原生字段。
    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate, FileTemplateNameControl {
        let target: FileTemplateNameTarget
        let nativeField: FileTemplateNameNativeField
        var session: FileTemplateNameEditingSession
        var allowsEditing: () -> Bool
        var save: (String) async throws -> Void

        // 在事件入口读取当前阶段，避免下一次视图更新前开放并发编辑。
        var canBeginEditing: Bool { allowsEditing() }

        var displayedValue: String {
            nativeField.currentEditor()?.string ?? nativeField.stringValue
        }

        init(
            template: FileTemplate,
            field: FileTemplateNameField,
            session: FileTemplateNameEditingSession,
            allowsEditing: @escaping () -> Bool,
            save: @escaping (String) async throws -> Void
        ) {
            target = FileTemplateNameTarget(templateID: template.id, field: field)
            nativeField = FileTemplateNameNativeField(frame: .zero)
            self.session = session
            self.allowsEditing = allowsEditing
            self.save = save
            super.init()

            nativeField.editingCoordinator = self
            nativeField.delegate = self
            nativeField.stringValue = field.value(in: template)
            nativeField.isEditable = true
            nativeField.isSelectable = true
            nativeField.isBordered = false
            nativeField.isBezeled = false
            nativeField.drawsBackground = false
            nativeField.focusRingType = .none
            nativeField.maximumNumberOfLines = 1
            nativeField.cell?.isScrollable = true
            nativeField.lineBreakMode = .byTruncatingTail
            nativeField.font = .systemFont(ofSize: field == .displayName
                ? NSFont.systemFontSize : NSFont.smallSystemFontSize)
            nativeField.textColor = field == .displayName ? .labelColor : .secondaryLabelColor
            nativeField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            nativeField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            nativeField.setAccessibilityLabel(String(localized: field == .displayName
                ? FileTemplatesText.displayName : FileTemplatesText.defaultFileName))
            let fieldName = field == .displayName ? "display-name" : "default-file-name"
            nativeField.identifier = NSUserInterfaceItemIdentifier(
                "file-template.\(template.id.rawValue.uuidString).\(fieldName)"
            )
        }

        func requestEditing() {
            guard canBeginEditing else { return }
            session.requestEditing(self, save: save)
        }

        /// 在冻结输入前完成输入法标记，保存字段编辑器中最新的完整文字。
        func prepareToCommit() -> String {
            if let editor = nativeField.currentEditor() as? NSTextView {
                if editor.hasMarkedText() { editor.unmarkText() }
                return editor.string
            }
            return nativeField.stringValue
        }

        func beginEditing(_ value: String) {
            guard nativeField.window != nil, nativeField.isEnabled, canBeginEditing else { return }
            // 文件操作可能刚完成，原生控件的下一次更新尚未发生。
            if !nativeField.isEditable { nativeField.isEditable = true }
            if !nativeField.isSelectable { nativeField.isSelectable = true }
            if let editor = nativeField.currentEditor() {
                if editor.string != value { editor.string = value }
            } else if nativeField.stringValue != value {
                nativeField.stringValue = value
            }
            nativeField.selectText(nil)
            setInputEnabled(true)
        }

        func finishEditing(_ value: String) {
            if let editor = nativeField.currentEditor(),
               let window = nativeField.window, window.firstResponder === editor {
                (editor as? NSTextView)?.isEditable = true
                window.makeFirstResponder(nil)
            }
            if nativeField.stringValue != value { nativeField.stringValue = value }
        }

        func setInputEnabled(_ enabled: Bool) {
            (nativeField.currentEditor() as? NSTextView)?.isEditable = enabled
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard !session.isEditing(self) else { return }
            setInputEnabled(false)
            requestEditing()
        }

        func controlTextDidChange(_ notification: Notification) {
            session.valueDidChange(displayedValue, from: self)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            session.editingDidEnd(self)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                session.cancelEditing()
            case #selector(NSResponder.insertNewline(_:)):
                Task { await session.finishEditing() }
            case #selector(NSResponder.insertTab(_:)):
                finishEditingAndMoveKeyView(forward: true)
            case #selector(NSResponder.insertBacktab(_:)):
                finishEditingAndMoveKeyView(forward: false)
            default:
                return false
            }
            return true
        }

        private func finishEditingAndMoveKeyView(forward: Bool) {
            Task {
                guard await session.finishEditing(), let window = nativeField.window else { return }
                if forward {
                    window.selectKeyView(following: nativeField)
                } else {
                    window.selectKeyView(preceding: nativeField)
                }
            }
        }
    }
}

/// 鼠标按下时保留切换目标；已在编辑的字段继续使用原生光标与选区行为。
@MainActor
final class FileTemplateNameNativeField: NSTextField {
    weak var editingCoordinator: FileTemplateNameTextField.Coordinator?

    /// 键盘与辅助功能的焦点请求也须在原生编辑器接收输入前取得批准。
    override func becomeFirstResponder() -> Bool {
        guard isEditingApproved else { return false }
        return super.becomeFirstResponder()
    }

    override func selectText(_ sender: Any?) {
        guard isEditingApproved else { return }
        // 重选已有文字不重新启动原生编辑周期，避免产生额外的结束编辑通知。
        if let editor = currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            return
        }
        super.selectText(sender)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let coordinator = editingCoordinator, coordinator.canBeginEditing else { return }
        if coordinator.session.isEditing(coordinator), !coordinator.session.isTransitioning {
            super.mouseDown(with: event)
        } else {
            coordinator.requestEditing()
        }
    }

    private var isEditingApproved: Bool {
        guard isEnabled, let coordinator = editingCoordinator, coordinator.canBeginEditing else { return false }
        guard coordinator.session.isEditing(coordinator) else {
            coordinator.requestEditing()
            return false
        }
        return true
    }
}

import AppKit
import SwiftUI

/// 预览专用模板数据，不读取或写入真实模板库。
@MainActor
enum FileTemplatePreviewFixtures {
    static let templates: [FileTemplate] = {
        do {
            return [
                try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt"),
                try FileTemplate(displayName: "TXT 2", defaultFileName: "untitled.txt"),
                try FileTemplate(displayName: "Markdown", defaultFileName: "notes.md"),
            ]
        } catch {
            preconditionFailure("File-template preview fixtures must be valid: \(error)")
        }
    }()

    static func state(_ templateState: FileTemplatePageState) -> StatusPagePreviewState {
        StatusPagePreviewState(
            isExtensionEnabled: true,
            loginItemState: .notRegistered,
            configuration: .standard,
            applicationIcons: [:],
            fileTemplateState: templateState
        )
    }
}

@MainActor
enum StatusPageFileTemplatesPreview: ApplicationPreview {
    static let id = "status-page-file-templates"

    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .fileTemplates,
            state: FileTemplatePreviewFixtures.state(
                .ready(FileTemplatePreviewFixtures.templates)
            )
        )
    }
}

@MainActor
enum StatusPageFileTemplatesEmptyPreview: ApplicationPreview {
    static let id = "status-page-file-templates-empty"

    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .fileTemplates,
            state: FileTemplatePreviewFixtures.state(.ready([]))
        )
    }
}

@MainActor
enum StatusPageFileTemplatesFailurePreview: ApplicationPreview {
    static let id = "status-page-file-templates-failure"

    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .fileTemplates,
            state: FileTemplatePreviewFixtures.state(
                .failed(CocoaError(.fileReadNoPermission).localizedDescription)
            )
        )
    }
}

/// 直接呈现生产编辑表单，检查双语标签、输入框和保存按钮布局。
@MainActor
enum FileTemplateEditorPreview: ApplicationPreview {
    static let id = "file-template-editor"

    static func present() -> AnyObject {
        let hostingController = NSHostingController(
            rootView: FileTemplateEditor(
                template: FileTemplatePreviewFixtures.templates[0],
                save: { _ in }
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: FileTemplatesText.edit)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        hostingController.view.layoutSubtreeIfNeeded()
        window.setContentSize(hostingController.view.fittingSize)
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return controller
    }
}

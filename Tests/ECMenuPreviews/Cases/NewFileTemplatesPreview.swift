/**
 提供模板设置页的有内容、空库和读取失败预览。
 以独立内存模板及页面状态驱动生产界面，便于检查列表和恢复入口。
 */

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
enum StatusPageNewFileTemplatesPreview: ApplicationPreview {
    static let id = "status-page-file-templates"

    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .newFileTemplates,
            state: FileTemplatePreviewFixtures.state(
                .ready(FileTemplatePreviewFixtures.templates)
            )
        )
    }
}

@MainActor
enum StatusPageNewFileTemplatesEmptyPreview: ApplicationPreview {
    static let id = "status-page-file-templates-empty"

    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .newFileTemplates,
            state: FileTemplatePreviewFixtures.state(.ready([]))
        )
    }
}

@MainActor
enum StatusPageNewFileTemplatesFailurePreview: ApplicationPreview {
    static let id = "status-page-file-templates-failure"

    static func present() -> AnyObject {
        StatusPagePreviewSession(
            selectedPane: .newFileTemplates,
            state: FileTemplatePreviewFixtures.state(
                .failed(CocoaError(.fileReadNoPermission).localizedDescription)
            )
        )
    }
}

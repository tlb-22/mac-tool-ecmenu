/**
 组成模板管理页的有序清单、拖拽、名称编辑、操作控件与加载错误界面。
 集中模板页面使用的布局和文案，通过注入的状态、编辑会话与操作回调绑定交互。
 */

import SwiftUI

/// 文件模板页面的布局调节入口；页面通用参数沿用 StatusPageStyle。
enum NewFileTemplatesStyle {
    /// 命令名与默认文件名控件之间的额外间距；控件本身保留系统内边距。
    static let rowNameSpacing: CGFloat = 0
    /// 模板行的水平与垂直内边距。
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 4
    /// 左侧名称区域在模板行内额外增加的缩进。
    static let nameLeadingPadding: CGFloat = 4
    /// 打开、更换和删除操作之间的间距。
    static let actionSpacing: CGFloat = 8
    /// 仅在文件读写持续一段时间后显示进度，避免短操作闪现指示器。
    static let operationProgressDelay: Duration = .milliseconds(300)
}

/// 模板管理的呈现层；名称、排序和文件操作分别提交。
struct NewFileTemplateSettingsPage: View {
    let state: FileTemplatePageState
    let isUpdating: Bool
    @ObservedObject var nameEditing: FileTemplateNameEditingSession
    @ObservedObject var actions: FileTemplatePageActions
    let importTemplate: () async throws -> Void
    let updateName: (FileTemplateID, FileTemplateNameField, String) async throws -> Void
    let openTemplate: (FileTemplateID) async throws -> Void
    let replaceTemplate: (FileTemplateID) async throws -> Void
    let removeTemplate: (FileTemplateID) async throws -> Void
    let moveTemplate: (FileTemplateID, FileTemplateID?) async throws -> Void
    let reload: () async -> Void
    @State private var dragNameCommit: Task<Bool, Never>?

    var body: some View {
        VStack(spacing: StatusPageStyle.sectionSpacing) {
            switch state {
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .failed(let message):
                Spacer()
                Text(NewFileTemplatesText.loadFailed)
                    .font(.headline)
                Text(verbatim: message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await reload() }
                } label: {
                    Text(NewFileTemplatesText.retry)
                }
                Spacer()
            case .ready(let templates):
                templateList(templates)

                HStack {
                    Button {
                        perform(importTemplate)
                    } label: {
                        Label {
                            Text(NewFileTemplatesText.add)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }

                    Spacer()

                    if actions.isPerforming && isUpdating {
                        FileTemplateOperationProgress()
                    }
                }
            }
        }
        .padding(StatusPageStyle.contentPadding)
        .background { editingBackground }
        .onDisappear {
            Task { await nameEditing.finishEditing() }
        }
        .alert(
            Text(NewFileTemplatesText.operationFailed),
            isPresented: Binding(
                get: { actions.errorMessage != nil },
                set: { if !$0 { actions.errorMessage = nil } }
            )
        ) {
            Button {
                actions.errorMessage = nil
            } label: {
                Text(NewFileTemplatesText.ok)
            }
        } message: {
            Text(verbatim: actions.errorMessage ?? "")
        }
    }

    private func templateList(_ templates: [FileTemplate]) -> some View {
        GroupBox {
            if templates.isEmpty {
                VStack(spacing: StatusPageStyle.rowSpacing) {
                    Text(NewFileTemplatesText.emptyTitle)
                    Text(NewFileTemplatesText.emptyDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SettingsReorderList(
                    rows: templates, allowsMoving: !actions.isPerforming,
                    dragBegan: { dragNameCommit = nameEditing.requestFinishing() },
                    dragEnded: { dragNameCommit = nil },
                    move: dropMove
                ) { template in
                    VStack(spacing: 0) {
                        templateRow(template)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editingBackground: some View {
        FileTemplateEditingBackground {
            nameEditing.requestFinishing()
        }
        .accessibilityHidden(true)
    }

    private func templateRow(_ template: FileTemplate) -> some View {
        HStack(spacing: StatusPageStyle.rowSpacing) {
            reorderHandle(for: template)
            VStack(alignment: .leading, spacing: NewFileTemplatesStyle.rowNameSpacing) {
                name(template, field: .displayName)
                name(template, field: .defaultFileName)
            }
            .padding(.leading, NewFileTemplatesStyle.nameLeadingPadding)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: NewFileTemplatesStyle.actionSpacing) {
                Button {
                    perform { try await openTemplate(template.id) }
                } label: {
                    Text(NewFileTemplatesText.open)
                }
                .help(Text(NewFileTemplatesText.openHelp))

                Button {
                    perform { try await replaceTemplate(template.id) }
                } label: {
                    Text(NewFileTemplatesText.replace)
                }
                .help(Text(NewFileTemplatesText.replaceHelp))

                Button(role: .destructive) {
                    perform { try await removeTemplate(template.id) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help(Text(NewFileTemplatesText.delete))
                .accessibilityLabel(Text(NewFileTemplatesText.delete))
            }
        }
        .padding(.horizontal, NewFileTemplatesStyle.rowHorizontalPadding)
        .padding(.vertical, NewFileTemplatesStyle.rowVerticalPadding)
    }

    private func name(_ template: FileTemplate, field: FileTemplateNameField) -> some View {
        let target = FileTemplateNameTarget(templateID: template.id, field: field)
        return FileTemplateNameTextField(
            template: template,
            field: field,
            session: nameEditing,
            allowsEditing: { actions.allowsNameEditing(target, in: nameEditing) },
            save: { value in try await updateName(template.id, field, value) }
        )
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        actions.perform(finishing: nameEditing, operation: operation)
    }

    private func reorderHandle(for template: FileTemplate) -> some View {
        let ids = state.templates!.map(\.id)
        let index = ids.firstIndex(of: template.id)!
        return SettingsReorderHandle(
            title: template.displayName,
            moveUp: index > 0 ? { move(template.id, before: ids[index - 1]) } : nil,
            moveDown: index + 1 < ids.count
                ? { move(template.id, before: ids.dropFirst(index + 2).first) } : nil
        )
        .frame(width: 20, height: 24)
    }

    private func move(_ id: FileTemplateID, before destination: FileTemplateID?) {
        perform { try await moveTemplate(id, destination) }
    }

    private func dropMove(_ id: FileTemplateID, before destination: FileTemplateID?) {
        // 原生 List 的辅助功能移动也走 onMove，此时没有鼠标拖拽会话。
        let commit = dragNameCommit ?? nameEditing.requestFinishing()
        actions.perform(afterNameCommit: commit) {
            try await moveTemplate(id, destination)
        }
    }
}

/// 短操作保持底部稳定；视图移除时取消尚未到期的进度显示。
private struct FileTemplateOperationProgress: View {
    @State private var isVisible = false

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(!isVisible)
            .task {
                do {
                    try await Task.sleep(for: NewFileTemplatesStyle.operationProgressDelay)
                } catch {
                    return
                }
                isVisible = true
            }
    }
}

/// 模板页面与文件选择器共用的产品用语。
enum NewFileTemplatesText {
    static let open = LocalizedStringResource(
        "fileTemplates.action.open", defaultValue: "Open",
        comment: "Opens the saved template file with its default application"
    )
    static let openHelp = LocalizedStringResource(
        "fileTemplates.action.open.help", defaultValue: "Open with the default application",
        comment: "Help for the template file open button"
    )
    static let replace = LocalizedStringResource(
        "fileTemplates.action.replace", defaultValue: "Replace…",
        comment: "Chooses another ordinary file to replace the saved template"
    )
    static let replaceHelp = LocalizedStringResource(
        "fileTemplates.action.replace.help", defaultValue: "Replace the template file",
        comment: "Explains how the template file is replaced"
    )
    static let add = LocalizedStringResource(
        "fileTemplates.action.add", defaultValue: "Add Template…",
        comment: "Button that imports an ordinary file as a template"
    )
    static let delete = LocalizedStringResource(
        "fileTemplates.action.delete", defaultValue: "Delete Template",
        comment: "Button that deletes an application's template copy"
    )
    static let displayName = LocalizedStringResource(
        "fileTemplates.field.displayName", defaultValue: "Display Name:",
        comment: "Label for a template's context-menu title"
    )
    static let defaultFileName = LocalizedStringResource(
        "fileTemplates.field.defaultFileName", defaultValue: "Default File Name:",
        comment: "Label for the initial filename used when copying a template"
    )
    static let emptyTitle = LocalizedStringResource(
        "fileTemplates.empty.title", defaultValue: "No File Templates",
        comment: "Title of the valid empty file-template list"
    )
    static let emptyDescription = LocalizedStringResource(
        "fileTemplates.empty.description",
        defaultValue: "Add a file to use it as a template in Finder.",
        comment: "Guidance for adding the first file template"
    )
    static let loadFailed = LocalizedStringResource(
        "fileTemplates.error.load", defaultValue: "Unable to Load Templates",
        comment: "Title shown when the template library cannot be read"
    )
    static let operationFailed = LocalizedStringResource(
        "fileTemplates.error.operation", defaultValue: "Operation Couldn’t Be Completed",
        comment: "Title of a failed template operation alert"
    )
    static let retry = LocalizedStringResource(
        "common.retry", defaultValue: "Retry",
        comment: "Button that retries an operation"
    )
    static let ok = LocalizedStringResource(
        "common.ok", defaultValue: "OK",
        comment: "Button that dismisses an informational alert"
    )
}

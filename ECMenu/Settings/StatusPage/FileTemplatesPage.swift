import SwiftUI

/// 模板管理的纯呈现层；导入、存储和重试均经由注入的操作执行。
struct FileTemplatesPage: View {
    let state: FileTemplatePageState
    let isUpdating: Bool
    let importTemplate: () async throws -> Void
    let updateTemplate: (FileTemplate) async throws -> Void
    let removeTemplate: (FileTemplateID) async throws -> Void
    let reload: () async -> Void

    @State private var editingTemplate: FileTemplate?
    @State private var operationError: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: StatusPageStyle.sectionSpacing) {
            switch state {
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .failed(let message):
                Spacer()
                Text(FileTemplatesText.loadFailed)
                    .font(.headline)
                Text(verbatim: message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await reload() }
                } label: {
                    Text(FileTemplatesText.retry)
                }
                Spacer()
            case .ready(let templates):
                templateList(templates)

                HStack {
                    Button {
                        isImporting = true
                        Task {
                            defer { isImporting = false }
                            do {
                                try await importTemplate()
                            } catch {
                                operationError = error.localizedDescription
                            }
                        }
                    } label: {
                        Label {
                            Text(FileTemplatesText.add)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(isUpdating || isImporting)

                    Spacer()

                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(StatusPageStyle.contentPadding)
        .sheet(item: $editingTemplate) { template in
            FileTemplateEditor(template: template, save: updateTemplate)
        }
        .alert(
            Text(FileTemplatesText.operationFailed),
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button {
                operationError = nil
            } label: {
                Text(FileTemplatesText.ok)
            }
        } message: {
            Text(verbatim: operationError ?? "")
        }
    }

    private func templateList(_ templates: [FileTemplate]) -> some View {
        GroupBox {
            if templates.isEmpty {
                VStack(spacing: StatusPageStyle.rowSpacing) {
                    Text(FileTemplatesText.emptyTitle)
                    Text(FileTemplatesText.emptyDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(templates) { template in
                            templateRow(template)
                            if template.id != templates.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func templateRow(_ template: FileTemplate) -> some View {
        HStack(spacing: StatusPageStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: template.displayName)
                    .lineLimit(1)
                Text(verbatim: template.defaultFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                editingTemplate = template
            } label: {
                Image(systemName: "pencil")
            }
            .help(Text(FileTemplatesText.edit))
            .accessibilityLabel(Text(FileTemplatesText.edit))

            Button(role: .destructive) {
                Task {
                    do {
                        try await removeTemplate(template.id)
                    } catch {
                        operationError = error.localizedDescription
                    }
                }
            } label: {
                Image(systemName: "trash")
            }
            .help(Text(FileTemplatesText.delete))
            .accessibilityLabel(Text(FileTemplatesText.delete))
        }
        .buttonStyle(.borderless)
        .disabled(isUpdating || isImporting)
        .padding(.horizontal, StatusPageStyle.rowHorizontalPadding)
        .padding(.vertical, 8)
    }
}

/// 编辑期间只保留输入草稿；点击保存后才创建有效模板并提交持久化。
struct FileTemplateEditor: View {
    let template: FileTemplate
    let save: (FileTemplate) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var defaultFileName: String
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(
        template: FileTemplate,
        save: @escaping (FileTemplate) async throws -> Void
    ) {
        self.template = template
        self.save = save
        _displayName = State(initialValue: template.displayName)
        _defaultFileName = State(initialValue: template.defaultFileName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(FileTemplatesText.edit)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    Text(FileTemplatesText.displayName)
                        .gridColumnAlignment(.trailing)
                    TextField(text: $displayName) {
                        Text(FileTemplatesText.displayName)
                    }
                }
                GridRow {
                    Text(FileTemplatesText.defaultFileName)
                    TextField(text: $defaultFileName) {
                        Text(FileTemplatesText.defaultFileName)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(isSaving)

            if let validationMessage {
                Text(verbatim: validationMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(FileTemplatesText.cancel)
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    saveChanges()
                } label: {
                    Text(FileTemplatesText.save)
                }
                .keyboardShortcut(.defaultAction)
            }
            .disabled(isSaving)
        }
        .padding(24)
        .frame(width: 440)
        .interactiveDismissDisabled(isSaving)
    }

    private func saveChanges() {
        let edited: FileTemplate
        do {
            edited = try FileTemplate(
                id: template.id,
                displayName: displayName,
                defaultFileName: defaultFileName
            )
        } catch {
            validationMessage = error.localizedDescription
            return
        }

        validationMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await save(edited)
                dismiss()
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }
}

/// 模板页面、编辑表单与文件选择器共用的产品用语。
enum FileTemplatesText {
    static let add = LocalizedStringResource(
        "fileTemplates.action.add", defaultValue: "Add Template…",
        comment: "Button that imports an ordinary file as a template"
    )
    static let edit = LocalizedStringResource(
        "fileTemplates.action.edit", defaultValue: "Edit Template",
        comment: "Title of the file-template editing sheet"
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
        "fileTemplates.error.operation", defaultValue: "Unable to Update Templates",
        comment: "Title of a failed template import or deletion alert"
    )
    static let retry = LocalizedStringResource(
        "common.retry", defaultValue: "Retry",
        comment: "Button that retries an operation"
    )
    static let save = LocalizedStringResource(
        "common.save", defaultValue: "Save",
        comment: "Button that saves the current edits"
    )
    static let cancel = LocalizedStringResource(
        "common.cancel", defaultValue: "Cancel",
        comment: "Button that cancels the current operation"
    )
    static let ok = LocalizedStringResource(
        "common.ok", defaultValue: "OK",
        comment: "Button that dismisses an informational alert"
    )
}

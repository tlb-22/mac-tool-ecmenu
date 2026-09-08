import SwiftUI

/// 文件模板页面的布局调节入口；页面通用参数沿用 StatusPageStyle。
enum FileTemplatesStyle {
    /// 命令名与默认文件名之间的间距。
    static let rowNameSpacing: CGFloat = 4
    /// 每个名称的最小高度，原地编辑前后保持一致。
    static let nameHeight: CGFloat = 18
    /// 模板行的水平与垂直内边距。
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 8
    /// 打开、更换和删除操作之间的间距。
    static let actionSpacing: CGFloat = 8
}

/// 模板管理的呈现层；每次名称编辑和文件操作分别提交。
struct FileTemplatesPage: View {
    let state: FileTemplatePageState
    let isUpdating: Bool
    @Binding var editingName: FileTemplateNameDraft?
    let importTemplate: () async throws -> Void
    let updateName: (FileTemplateID, FileTemplateNameField, String) async throws -> Void
    let openTemplate: (FileTemplateID) async throws -> Void
    let replaceTemplate: (FileTemplateID) async throws -> Void
    let removeTemplate: (FileTemplateID) async throws -> Void
    let reload: () async -> Void

    @FocusState private var focusedName: FileTemplateNameTarget?
    @State private var operationError: String?
    @State private var actionTask: Task<Void, Never>?

    private var isBusy: Bool { isUpdating || actionTask != nil }

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
                        perform(importTemplate)
                    } label: {
                        Label {
                            Text(FileTemplatesText.add)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(isBusy)

                    Spacer()

                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(StatusPageStyle.contentPadding)
        .onChange(of: focusedName) { previous, current in
            guard let draft = editingName,
                  draft.target == previous, current != previous else { return }
            Task { await finishEditing(draft) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if let draft = editingName { Task { await finishEditing(draft) } }
        }
        .onDisappear {
            if let draft = editingName { Task { await finishEditing(draft) } }
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
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func templateRow(_ template: FileTemplate) -> some View {
        HStack(spacing: StatusPageStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: FileTemplatesStyle.rowNameSpacing) {
                name(template, field: .displayName)
                name(template, field: .defaultFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: FileTemplatesStyle.actionSpacing) {
                Button {
                    perform { try await openTemplate(template.id) }
                } label: {
                    Text(FileTemplatesText.open)
                }
                .help(Text(FileTemplatesText.openHelp))

                Button {
                    perform { try await replaceTemplate(template.id) }
                } label: {
                    Text(FileTemplatesText.replace)
                }

                Button(role: .destructive) {
                    perform { try await removeTemplate(template.id) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help(Text(FileTemplatesText.delete))
                .accessibilityLabel(Text(FileTemplatesText.delete))
            }
            .disabled(isBusy)
        }
        .padding(.horizontal, FileTemplatesStyle.rowHorizontalPadding)
        .padding(.vertical, FileTemplatesStyle.rowVerticalPadding)
    }

    @ViewBuilder
    private func name(_ template: FileTemplate, field: FileTemplateNameField) -> some View {
        let target = FileTemplateNameTarget(templateID: template.id, field: field)
        let title = field == .displayName ? FileTemplatesText.displayName : FileTemplatesText.defaultFileName
        if let draft = editingName, draft.target == target {
            FileTemplateInlineNameEditor(
                draft: draft,
                title: title,
                focus: $focusedName,
                submit: { Task { await finishEditing(draft) } },
                cancel: {
                    editingName = nil
                    focusedName = nil
                }
            )
        } else {
            Button {
                perform {
                    let draft = FileTemplateNameDraft(template: template, field: field) { value in
                        try await updateName(template.id, field, value)
                    }
                    editingName = draft
                    focusedName = target
                }
            } label: {
                Text(verbatim: field.value(in: template))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: FileTemplatesStyle.nameHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(Text(title))
            .accessibilityValue(field.value(in: template))
        }
    }

    /// 失焦与点击后续操作可以同时到达；同一草稿负责合并提交。
    @discardableResult
    private func finishEditing(_ draft: FileTemplateNameDraft) async -> Bool {
        let saved = await draft.commit()
        guard editingName === draft else { return saved }
        if saved {
            editingName = nil
            focusedName = nil
        } else {
            focusedName = draft.target
        }
        return saved
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        guard actionTask == nil else { return }
        actionTask = Task {
            defer { actionTask = nil }
            if let draft = editingName, !(await finishEditing(draft)) { return }
            do {
                try await operation()
            } catch {
                operationError = error.localizedDescription
            }
        }
    }
}

/// 草稿通知只重绘当前字段，保留失败输入并支持重试或 Escape 放弃。
private struct FileTemplateInlineNameEditor: View {
    @ObservedObject var draft: FileTemplateNameDraft
    let title: LocalizedStringResource
    let focus: FocusState<FileTemplateNameTarget?>.Binding
    let submit: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FileTemplatesStyle.rowNameSpacing) {
            TextField(text: $draft.value) { Text(title) }
                .textFieldStyle(.plain)
                .frame(minHeight: FileTemplatesStyle.nameHeight)
                .focused(focus, equals: draft.target)
                .disabled(draft.isSaving)
                .onSubmit(submit)
                .onExitCommand(perform: cancel)
                .onAppear { focus.wrappedValue = draft.target }

            if let message = draft.errorMessage {
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 模板页面与文件选择器共用的产品用语。
enum FileTemplatesText {
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

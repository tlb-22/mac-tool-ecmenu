import Combine
import Foundation

/// 一次原地编辑只修改一个名称，另一个名称从最新已提交模板读取。
nonisolated enum FileTemplateNameField: Hashable, Sendable {
    case displayName
    case defaultFileName

    func value(in template: FileTemplate) -> String {
        switch self {
        case .displayName: template.displayName
        case .defaultFileName: template.defaultFileName
        }
    }

    func updating(_ template: FileTemplate, to value: String) throws -> FileTemplate {
        try FileTemplate(
            id: template.id,
            displayName: self == .displayName ? value : template.displayName,
            defaultFileName: self == .defaultFileName ? value : template.defaultFileName
        )
    }
}

nonisolated struct FileTemplateNameTarget: Hashable, Sendable {
    let templateID: FileTemplateID
    let field: FileTemplateNameField
}

/// 输入草稿拥有一次编辑的生命周期；回车、失焦和后续操作共享同一次提交。
@MainActor
final class FileTemplateNameDraft: ObservableObject {
    let target: FileTemplateNameTarget
    @Published var value: String
    @Published private(set) var errorMessage: String?

    private enum CommitState {
        case idle
        case saving(Task<Bool, Never>)
        case saved
    }

    @Published private var commitState = CommitState.idle
    let originalValue: String
    private let save: (String) async throws -> Void

    var isSaving: Bool {
        if case .saving = commitState { return true }
        return false
    }

    init(
        target: FileTemplateNameTarget,
        value: String,
        save: @escaping (String) async throws -> Void
    ) {
        self.target = target
        self.value = value
        originalValue = value
        self.save = save
    }

    func commit() async -> Bool {
        switch commitState {
        case .saved:
            return true
        case .saving(let task):
            return await task.value
        case .idle:
            guard value != originalValue else {
                commitState = .saved
                return true
            }
            let valueToSave = value
            let task = Task {
                do {
                    try await save(valueToSave)
                    errorMessage = nil
                    commitState = .saved
                    return true
                } catch {
                    errorMessage = error.localizedDescription
                    commitState = .idle
                    return false
                }
            }
            commitState = .saving(task)
            return await task.value
        }
    }
}

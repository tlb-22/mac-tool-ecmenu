/**
 持有一次模板名称字段编辑的目标、原始值、草稿和提交阶段。
 让并发的编辑结束请求共享同一次异步保存，并保留失败后可继续编辑的状态。
 */

import Foundation

nonisolated struct FileTemplateNameTarget: Hashable, Sendable {
    let templateID: FileTemplateID
    let field: FileTemplateNameField
}

/// 输入草稿拥有一次编辑的生命周期；回车、失焦和后续操作共享同一次提交。
@MainActor
final class FileTemplateNameDraft {
    let target: FileTemplateNameTarget
    var value: String

    private enum CommitState {
        case idle
        case saving(Task<Bool, Never>)
        case saved
    }

    private var commitState = CommitState.idle
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
                    commitState = .saved
                    return true
                } catch {
                    commitState = .idle
                    return false
                }
            }
            commitState = .saving(task)
            return await task.value
        }
    }
}

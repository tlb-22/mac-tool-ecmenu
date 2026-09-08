import Combine
import Foundation

/// 模板库在设置页中的读取状态；读取失败与有效的空清单分别呈现。
enum FileTemplatePageState: Equatable {
    case loading
    case ready([FileTemplate])
    case failed(String)

    /// 只有成功读取的清单才能用于构建菜单快照。
    var templates: [FileTemplate]? {
        guard case .ready(let templates) = self else { return nil }
        return templates
    }
}

/// 发布模板库已提交的快照；持久化和模板身份仍由模板库统一管理。
@MainActor
final class FileTemplateController: ObservableObject {
    @Published private(set) var state = FileTemplatePageState.loading
    @Published private(set) var isUpdating = false

    private let library: FileTemplateLibrary
    private let didChange: ([FileTemplate]) -> Void
    private var initialLoad: Task<Void, Never>?

    var templates: [FileTemplate]? { state.templates }

    init(
        library: FileTemplateLibrary,
        didChange: @escaping ([FileTemplate]) -> Void
    ) {
        self.library = library
        self.didChange = didChange
    }

    /// 启动与页面入口共享同一次初始化，不会补回用户已经删除的模板。
    func loadIfNeeded() async {
        if let initialLoad {
            await initialLoad.value
            return
        }
        let task = Task { await reload() }
        initialLoad = task
        await task.value
    }

    /// 读取失败后允许用户明确重试；错误保留为页面状态。
    func reload() async {
        state = .loading
        do {
            publish(try await library.load())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func importFile(at url: URL) async throws {
        try await perform { try await self.library.importFile(at: url) }
    }

    func updateTemplate(_ template: FileTemplate) async throws {
        try await perform { try await self.library.update(template) }
    }

    func updateName(for id: FileTemplateID, field: FileTemplateNameField, value: String) async throws {
        guard let template = templates?.first(where: { $0.id == id }) else {
            throw FileTemplateLibraryError.templateNotFound(id)
        }
        try await updateTemplate(field.updating(template, to: value))
    }

    func openTemplate(id: FileTemplateID) async throws {
        let url = try await library.fileURL(for: id)
        try FileTemplateFileServices.open(url)
    }

    func replaceTemplate(id: FileTemplateID, at url: URL) async throws {
        try await perform { try await self.library.replaceFile(for: id, at: url) }
    }

    func removeTemplate(id: FileTemplateID) async throws {
        try await perform { try await self.library.remove(id: id) }
    }

    /// 操作只发布库返回的完整快照；部分删除失败时取得已经提交的快照。
    private func perform(
        _ operation: () async throws -> [FileTemplate]
    ) async throws {
        precondition(!isUpdating && templates != nil)
        isUpdating = true
        defer { isUpdating = false }

        do {
            publish(try await operation())
        } catch {
            let operationError = error
            await reload()
            throw operationError
        }
    }

    private func publish(_ templates: [FileTemplate]) {
        state = .ready(templates)
        didChange(templates)
    }
}

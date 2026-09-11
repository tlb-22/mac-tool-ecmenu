/**
 协调模板页面文件操作的编辑收尾、进行中状态和失败反馈。
 先完成当前名称提交再执行注入的异步操作，并在页面切换时保留操作状态。
 */

import Combine
import Foundation

/// 文件操作随状态页窗口保留，页面切换不重置正在进行的操作与失败反馈。
@MainActor
final class FileTemplatePageActions: ObservableObject {
    private enum Phase {
        case idle
        case finishingName
        case performing
    }

    @Published private var phase = Phase.idle
    @Published var errorMessage: String?

    var isPerforming: Bool { phase == .performing }

    func allowsNameEditing(
        _ target: FileTemplateNameTarget,
        in session: FileTemplateNameEditingSession
    ) -> Bool {
        switch phase {
        case .idle: true
        case .finishingName: session.draft?.target == target
        case .performing: false
        }
    }

    func perform(
        finishing nameEditing: FileTemplateNameEditingSession,
        operation: @escaping () async throws -> Void
    ) {
        perform(preparing: { await nameEditing.finishEditing() }, operation: operation)
    }

    /// 放下时等待拖拽开始已发出的名称提交，不重复尝试一次已经失败的保存。
    func perform(
        afterNameCommit task: Task<Bool, Never>,
        operation: @escaping () async throws -> Void
    ) {
        perform(preparing: { await task.value }, operation: operation)
    }

    private func perform(
        preparing prepare: @escaping () async -> Bool,
        operation: @escaping () async throws -> Void
    ) {
        guard phase == .idle else { return }
        phase = .finishingName
        Task {
            defer { phase = .idle }
            guard await prepare() else { return }
            phase = .performing
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

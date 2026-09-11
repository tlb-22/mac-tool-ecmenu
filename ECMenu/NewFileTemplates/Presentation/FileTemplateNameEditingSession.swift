/**
 协调模板页面当前名称编辑目标、原生控件焦点与异步提交。
 保持活动控件身份稳定，统一处理切换字段、结束编辑和提交失败。
 */

import Combine

/// 原生焦点和文字读写集中在控件边界，编辑会话只负责提交与目标交接。
@MainActor
protocol FileTemplateNameControl: AnyObject {
    var target: FileTemplateNameTarget { get }
    var displayedValue: String { get }
    func prepareToCommit() -> String
    func beginEditing(_ value: String)
    func finishEditing(_ value: String)
    func setInputEnabled(_ enabled: Bool)
}

/// 状态页唯一的名称编辑会话；保存期间继续接收目标，最后一次选择决定交接位置。
@MainActor
final class FileTemplateNameEditingSession: ObservableObject {
    private struct Active {
        let draft: FileTemplateNameDraft
        let control: any FileTemplateNameControl
    }

    private enum Destination {
        case edit(any FileTemplateNameControl, (String) async throws -> Void)
        case finish
    }

    private final class Request {
        let destination: Destination

        init(_ destination: Destination) {
            self.destination = destination
        }
    }

    private struct Transition {
        let request: Request
        let task: Task<Bool, Never>
    }

    @Published private var active: Active?
    private var transition: Transition?

    var draft: FileTemplateNameDraft? { active?.draft }
    var isTransitioning: Bool { transition != nil }

    func isEditing(_ control: any FileTemplateNameControl) -> Bool {
        active?.control === control
    }

    @discardableResult
    func requestEditing(
        _ control: any FileTemplateNameControl,
        save: @escaping (String) async throws -> Void
    ) -> Task<Bool, Never> {
        if let active, active.control === control, transition == nil {
            control.beginEditing(active.draft.value)
            return Task { true }
        }
        return request(.edit(control, save))
    }

    @discardableResult
    func requestFinishing() -> Task<Bool, Never> {
        if let transition, case .finish = transition.request.destination {
            return transition.task
        }
        return request(.finish)
    }

    @discardableResult
    func finishEditing() async -> Bool {
        await requestFinishing().value
    }

    func cancelEditing() {
        guard transition == nil, let previous = active else { return }
        active = nil
        previous.control.finishEditing(previous.draft.originalValue)
    }

    func valueDidChange(_ value: String, from control: any FileTemplateNameControl) {
        guard let active, active.control === control else { return }
        if active.draft.value != value { active.draft.value = value }
    }

    func editingDidEnd(_ control: any FileTemplateNameControl) {
        guard let active, active.control === control,
              transition == nil || active.draft.isSaving else { return }
        // 保存挂起时，原生失焦仍更新最后目的地；失败后恢复焦点的同步通知不另开请求。
        requestFinishing()
    }

    @discardableResult
    private func request(_ destination: Destination) -> Task<Bool, Never> {
        let request = Request(destination)
        let task = Task { await resolve(request) }
        transition = Transition(request: request, task: task)
        return task
    }

    private func resolve(_ request: Request) async -> Bool {
        guard transition?.request === request else { return false }
        let previous = active
        if let previous {
            if !previous.draft.isSaving {
                let value = previous.control.prepareToCommit()
                if previous.draft.value != value { previous.draft.value = value }
            }
            previous.control.setInputEnabled(false)
            let saved = await previous.draft.commit()
            guard transition?.request === request else { return false }
            if !saved {
                previous.control.beginEditing(previous.draft.value)
                transition = nil
                return false
            }
        }

        // 先更新唯一所有者，再结束旧控件，旧控件的失焦通知不会清除新目标。
        switch request.destination {
        case .finish:
            active = nil
            if let previous { previous.control.finishEditing(previous.draft.value) }
        case .edit(let control, let save):
            let draft = FileTemplateNameDraft(target: control.target, value: control.displayedValue, save: save)
            active = Active(draft: draft, control: control)
            if let previous, previous.control !== control {
                previous.control.finishEditing(previous.draft.value)
            }
            control.beginEditing(draft.value)
        }
        transition = nil
        return true
    }
}

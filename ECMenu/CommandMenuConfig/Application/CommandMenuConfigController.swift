/**
 持有进程内唯一可变的命令菜单配置，并响应总开关与命令可见性变更。
 每次有效变更统一保存偏好并发布菜单失效通知。
 */

import Combine

/// 进程内菜单配置的唯一可变所有者，协调偏好更新与菜单失效提示。
@MainActor
final class CommandMenuConfigController: ObservableObject {
    @Published private(set) var configuration: CommandMenuConfig
    private let store: CommandMenuConfigStore
    private let publisher: MenuChangePublisher

    init(store: CommandMenuConfigStore, publisher: MenuChangePublisher) {
        self.store = store
        self.publisher = publisher
        configuration = store.load() ?? .standard
    }

    func setEnabled(_ isEnabled: Bool) {
        guard configuration.isEnabled != isEnabled else { return }
        configuration.setEnabled(isEnabled)
        persistAndPublish()
    }

    func setVisible(_ isVisible: Bool, for feature: ContextCommandFeatureID) {
        guard configuration.isVisible(feature) != isVisible else { return }
        configuration.setVisible(isVisible, for: feature)
        persistAndPublish()
    }

    private func persistAndPublish() {
        store.save(configuration)
        publisher.signal()
    }
}

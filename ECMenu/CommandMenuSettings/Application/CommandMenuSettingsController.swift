/**
 持有进程内唯一可变的命令菜单配置，并响应总开关、命令可见性和显示顺序变更。
 每次有效变更统一保存偏好并发布菜单失效通知。
 */

import Combine

/// 进程内菜单配置的唯一可变所有者，协调偏好更新与菜单失效提示。
@MainActor
final class CommandMenuSettingsController: ObservableObject {
    @Published private(set) var configuration: CommandMenuSettings
    private let store: CommandMenuSettingsStore
    private let publisher: MenuChangePublisher

    init(store: CommandMenuSettingsStore, publisher: MenuChangePublisher) {
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

    /// 一次完成的排序只提交一次；无位置变化时不保存或发布。
    func move(_ featureID: ContextCommandFeatureID, before nextFeatureID: ContextCommandFeatureID?) {
        var updated = configuration
        guard updated.move(featureID, before: nextFeatureID) else { return }
        configuration = updated
        persistAndPublish()
    }

    private func persistAndPublish() {
        store.save(configuration)
        publisher.signal()
    }
}

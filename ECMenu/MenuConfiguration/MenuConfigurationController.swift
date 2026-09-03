import Combine
import Foundation
import OSLog

/// 持有主应用中的菜单配置真相，并提示 Finder Extension 定向拉取更新。
@MainActor
final class MenuConfigurationController: ObservableObject {
    /// 状态页观察的当前有效配置。
    @Published private(set) var configuration: MenuConfiguration

    /// 持久化主应用配置的偏好存储。
    private let defaults: UserDefaults
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "MenuConfiguration"
    )

    /// 从持久化存储恢复配置；IPC Server 负责提供权威快照。
    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        configuration = Self.storedConfiguration(in: defaults)
            ?? .standard
    }

    /// 更新产品总开关，并保留每个功能原有的独立可见性配置。
    /// - Parameter isEnabled: 是否允许 Finder 贡献本产品的右键菜单。
    func setEnabled(_ isEnabled: Bool) {
        guard configuration.isEnabled != isEnabled else {
            return
        }

        configuration.setEnabled(isEnabled)
        storeConfiguration()
        signalConfigurationChange()
    }

    /// 更新一个功能的可见性，并持久化、发布新的配置快照。
    /// - Parameters:
    ///   - isVisible: 新的显示状态。
    ///   - feature: 要更新的右键功能。
    func setVisible(
        _ isVisible: Bool,
        for feature: ContextCommandFeatureID
    ) {
        guard configuration.isVisible(feature) != isVisible else {
            return
        }

        configuration.setVisible(isVisible, for: feature)
        storeConfiguration()
        signalConfigurationChange()
    }

    // MARK: - ==================== 副作用：持久化配置真相 ====================

    /// 从主应用偏好存储恢复有效配置。
    /// - Parameter defaults: 主应用持有的偏好存储。
    /// - Returns: 可解码配置；没有缓存或缓存无效时返回 `nil`。
    private static func storedConfiguration(
        in defaults: UserDefaults
    ) -> MenuConfiguration? {
        guard let data = defaults.data(
            forKey: MenuConfigurationChannel.persistedConfigurationKey
        ) else {
            return nil
        }
        do {
            return try MenuConfigurationChannel.decodedConfiguration(
                from: data
            )
        } catch {
            logger.error(
                "Could not decode the stored menu configuration: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// 编码当前配置并写入主应用偏好存储。
    private func storeConfiguration() {
        let data = MenuConfigurationChannel.encodedData(
            for: configuration
        )
        defaults.set(
            data,
            forKey: MenuConfigurationChannel.persistedConfigurationKey
        )
    }

    /// 通知 Extension 通过已验证 socket 拉取，而不把配置放入广播正文。
    private func signalConfigurationChange() {
        MenuConfigurationChannel.signalConfigurationChange()
        Self.logger.info(
            "Signaled menu configuration change: enabled=\(self.configuration.isEnabled), hiddenFeatures=\(self.configuration.hiddenFeatureIDs.count)"
        )
    }
}

import Foundation
import OSLog

/// Finder Extension 保存的最后一份有效菜单配置，只接受主应用发布的更新。
final class MenuConfigurationReplica: NSObject {
    /// 当前用于构建 Finder 菜单的配置快照。
    private var configuration: MenuConfiguration

    /// 在主应用不可用时恢复最后有效快照的本地偏好存储。
    private let defaults: UserDefaults

    /// 只接受精确主应用签名响应的定向 socket 客户端。
    private let transport: (any MenuConfigurationRequesting)?

    /// 同一时刻最多存在一个配置拉取，避免响应乱序覆盖新状态。
    private var isRefreshInFlight = false

    /// 拉取期间又收到变更信号时，在当前连接结束后再读取一次最终真相。
    private var refreshRequestedWhileInFlight = false
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "MenuConfiguration"
    )

    /// 恢复缓存、监听无数据更新信号并向主应用定向拉取配置。
    override convenience init() {
        let transport: AuthenticatedLocalSocketClient?
        do {
            transport = try AuthenticatedLocalSocketClient(
                expectedServerSigningIdentifier:
                    ApplicationIPC.applicationSigningIdentifier
            )
        } catch {
            transport = nil
            Self.logger.error(
                "Could not initialize authenticated local IPC: \(error.localizedDescription, privacy: .public)"
            )
        }
        self.init(defaults: .standard, transport: transport)
    }

    /// 注入缓存和 transport，供同步并发策略测试使用。
    init(
        defaults: UserDefaults,
        transport: (any MenuConfigurationRequesting)?
    ) {
        self.defaults = defaults
        self.transport = transport
        configuration = Self.storedConfiguration(in: defaults)
            ?? .standard
        super.init()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleConfigurationChangeSignal(_:)),
            name: MenuConfigurationChannel.didChangeNotification,
            object: nil
        )
        refreshConfiguration()
    }

    /// 释放配置通知观察者。
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// 查询产品当前是否应向 Finder 贡献任何右键菜单项。
    var isEnabled: Bool {
        configuration.isEnabled
    }

    /// 查询功能自身的显示配置，不合并产品总开关。
    /// - Parameter feature: 固定右键功能标识。
    /// - Returns: 功能未被独立隐藏时为 `true`。
    func isVisible(_ feature: ContextCommandFeatureID) -> Bool {
        configuration.isVisible(feature)
    }

    /// 无数据广播只能触发拉取，本身不能改变任何菜单状态。
    @objc private func handleConfigurationChangeSignal(
        _ notification: Notification
    ) {
        refreshConfiguration()
    }

    /// 通过双向身份验证的 socket 请求主应用当前真相。
    func refreshConfiguration() {
        guard let transport else {
            Self.logger.error("Authenticated local IPC is unavailable")
            return
        }
        guard !isRefreshInFlight else {
            refreshRequestedWhileInFlight = true
            return
        }

        isRefreshInFlight = true

        transport.fetchMenuConfiguration { [self] result in
            Task { @MainActor [self] in
                self.isRefreshInFlight = false
                let shouldRefreshAgain =
                    self.refreshRequestedWhileInFlight
                self.refreshRequestedWhileInFlight = false

                // 拉取期间出现新信号时，当前响应可能已经过时；不应用它，
                // 等下一次已验证读取返回最终真相。
                if !shouldRefreshAgain {
                    self.applyRefreshResult(result)
                }
                if shouldRefreshAgain {
                    self.refreshConfiguration()
                }
            }
        }
    }

    /// 验证、应用并缓存一次没有被后续信号淘汰的响应。
    private func applyRefreshResult(
        _ result: Result<MenuConfiguration, Error>
    ) {
        guard case let .success(updated) = result else {
            if case let .failure(error) = result {
                Self.logger.error(
                    "Could not refresh menu configuration: \(error.localizedDescription, privacy: .public)"
                )
            }
            return
        }

        configuration = updated
        storeConfiguration(updated)
        Self.logger.info(
            "Applied menu configuration: enabled=\(updated.isEnabled), hiddenFeatures=\(updated.hiddenFeatureIDs.count)"
        )
    }

    // MARK: - ==================== 副作用：缓存配置副本 ====================

    /// 从 Extension 偏好存储恢复最后一份有效快照。
    /// - Parameter defaults: Extension 持有的偏好存储。
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
                "Could not decode the cached menu configuration: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// 编码并缓存一份 Extension 可独立恢复的配置快照。
    /// - Parameter configuration: 主应用刚发布的有效配置。
    private func storeConfiguration(_ configuration: MenuConfiguration) {
        let data = MenuConfigurationChannel.encodedData(
            for: configuration
        )
        defaults.set(
            data,
            forKey: MenuConfigurationChannel.persistedConfigurationKey
        )
    }
}

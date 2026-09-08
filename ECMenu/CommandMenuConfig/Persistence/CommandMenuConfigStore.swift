/**
 使用 UserDefaults 读取和保存命令菜单偏好。
 沿用共享通道定义的存储键与编码契约，并记录读取解码失败。
 */

import Foundation
import OSLog

/// 主应用菜单偏好的唯一存储适配，保持已发布键与编码格式。
@MainActor
struct CommandMenuConfigStore {
    let defaults: UserDefaults
    private static let logger = Logger(subsystem: ApplicationLogging.subsystem, category: "CommandMenuConfig")

    func load() -> CommandMenuConfig? {
        guard let data = defaults.data(forKey: CommandMenuConfigChannel.persistedConfigurationKey) else { return nil }
        do {
            return try CommandMenuConfigChannel.decodedConfiguration(from: data)
        } catch {
            Self.logger.error("Could not decode the stored menu configuration: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ configuration: CommandMenuConfig) {
        defaults.set(CommandMenuConfigChannel.encodedData(for: configuration),
                     forKey: CommandMenuConfigChannel.persistedConfigurationKey)
    }
}

/**
 集中维护主应用菜单偏好的稳定键和纯编码入口，使保存与独立迁移使用同一份格式契约。
 系统通知的发送由平台适配实现，配置字节本身只表达有效菜单开关。
 */

import Foundation

/// 定义菜单配置的稳定偏好键和纯编解码格式。
nonisolated enum CommandMenuConfigChannel {
    /// 主应用保存菜单开关时使用的稳定偏好键；格式版本保存在值内部。
    static let persistedConfigurationKey = "menu-configuration-v1"

    /// 把配置编码为持久化或传输使用的数据。
    /// - Parameter configuration: 需要编码的配置快照。
    /// - Returns: 当前格式的编码数据。
    static func encodedData(for configuration: CommandMenuConfig) -> Data {
        try! JSONEncoder().encode(configuration)
    }

    /// 从持久化数据解码并验证配置版本。
    /// - Parameter data: 编码后的配置数据。
    /// - Returns: 当前格式的配置。
    static func decodedConfiguration(from data: Data) throws -> CommandMenuConfig {
        try JSONDecoder().decode(CommandMenuConfig.self, from: data)
    }
}

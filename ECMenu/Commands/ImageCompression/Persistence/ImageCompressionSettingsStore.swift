/**
 保存并恢复用户最后确认的图片压缩参数。
 通过 UserDefaults 的独立字段读取值，再由领域规则恢复有效设置。
 */

import Foundation

// MARK: - ==================== 副作用：设置持久化 ====================

/// 通过可替换的 `UserDefaults` 读取和保存压缩图片功能设置。
nonisolated struct ImageCompressionSettingsStore {
    /// 最大宽度使用的稳定偏好键。
    static let maximumWidthKey = "image-compression.maximum-width"

    /// 整数质量使用的稳定偏好键。
    static let qualityKey = "image-compression.quality"

    /// 主应用生产环境或测试隔离套件提供的偏好容器。
    private let defaults: UserDefaults

    /// 使用装配层提供的偏好容器。
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 恢复最后确认的设置；每个缺失或无效字段独立回退默认值。
    func load() -> ImageCompressionSettings {
        let storedWidth = defaults.object(
            forKey: Self.maximumWidthKey
        ) as? Int
        let storedQuality = defaults.object(
            forKey: Self.qualityKey
        ) as? Int

        return ImageCompressionSettings.restoring(
            maximumWidth: storedWidth,
            quality: storedQuality
        )
    }

    /// 只在用户确认设置窗口后持久化完整设置。
    func save(_ settings: ImageCompressionSettings) {
        defaults.set(settings.maximumWidth, forKey: Self.maximumWidthKey)
        defaults.set(settings.quality, forKey: Self.qualityKey)
    }
}

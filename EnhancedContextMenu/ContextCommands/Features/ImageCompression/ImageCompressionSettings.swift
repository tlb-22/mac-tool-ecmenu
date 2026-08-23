import Foundation

// MARK: - ==================== 领域规则 ====================

/// 集中定义目标宽度的有效范围和默认值。
nonisolated enum ImageCompressionWidthRules {
    /// 目标宽度允许的最小正整数。
    static let minimum = 1

    /// 默认目标宽度，单位为像素。
    static let standard = 1_440
}

/// 集中定义用户质量刻度及其 ImageIO 映射。
nonisolated enum ImageCompressionQualityScale {
    /// 用户可选的最低质量刻度。
    static let minimum = 0

    /// 用户可选的最高质量刻度。
    static let maximum = 10

    /// 默认 JPG 质量刻度。
    static let standard = 8

    /// 滑块需要显示的全部整数刻度数量。
    static let tickCount = maximum - minimum + 1

    /// 质量设置允许的完整闭区间。
    static let validValues = minimum...maximum

    /// 把界面刻度线性映射为 ImageIO 使用的 `0.0...1.0`。
    static func imageIOValue(for value: Int) -> Double {
        Double(value - minimum) / Double(maximum - minimum)
    }
}

// MARK: - ==================== 类型化设置 ====================

/// 用户确认后用于整批图片压缩的持久化设置。
nonisolated struct ImageCompressionSettings: Equatable, Sendable {
    /// 没有持久化设置时使用的脚本同款默认值。
    static let standard = ImageCompressionSettings(
        maximumWidth: ImageCompressionWidthRules.standard,
        quality: ImageCompressionQualityScale.standard
    )

    /// 输出允许达到的最大视觉宽度，单位为像素。
    let maximumWidth: Int

    /// 用户界面中的整数质量，范围为 `0...10`。
    let quality: Int

    /// ImageIO 接收的 `0.0...1.0` 线性压缩质量。
    var imageIOQuality: Double {
        ImageCompressionQualityScale.imageIOValue(for: quality)
    }

    /// 创建一个已经通过用户输入边界验证的压缩设置。
    init(maximumWidth: Int, quality: Int) {
        precondition(maximumWidth >= ImageCompressionWidthRules.minimum)
        precondition(ImageCompressionQualityScale.validValues.contains(quality))

        self.maximumWidth = maximumWidth
        self.quality = quality
    }
}

// MARK: - ==================== 副作用：设置持久化 ====================

/// 通过可替换的 `UserDefaults` 读取和保存压缩图片功能设置。
nonisolated struct ImageCompressionSettingsStore {
    /// 最大宽度使用的稳定偏好键。
    static let maximumWidthKey = "image-compression.maximum-width"

    /// 整数质量使用的稳定偏好键。
    static let qualityKey = "image-compression.quality"

    /// 主应用生产环境或测试隔离套件提供的偏好容器。
    private let defaults: UserDefaults

    /// 构造默认使用主应用偏好、也允许测试注入独立套件的存储边界。
    init(defaults: UserDefaults = .standard) {
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

        let maximumWidth = storedWidth.flatMap { value in
            value >= ImageCompressionWidthRules.minimum ? value : nil
        } ?? ImageCompressionSettings.standard.maximumWidth
        let quality = storedQuality.flatMap { value in
            ImageCompressionQualityScale.validValues.contains(value)
                ? value
                : nil
        } ?? ImageCompressionSettings.standard.quality

        return ImageCompressionSettings(
            maximumWidth: maximumWidth,
            quality: quality
        )
    }

    /// 只在用户确认设置窗口后持久化完整设置。
    func save(_ settings: ImageCompressionSettings) {
        defaults.set(settings.maximumWidth, forKey: Self.maximumWidthKey)
        defaults.set(settings.quality, forKey: Self.qualityKey)
    }
}

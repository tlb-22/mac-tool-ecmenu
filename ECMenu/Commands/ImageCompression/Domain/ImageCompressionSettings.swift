/**
 定义有效的压缩宽度、质量刻度及其 ImageIO 映射。
 在构造和持久化恢复时应用集中规则，使执行阶段只接收有效参数。
 */

import Foundation

// MARK: - ==================== 领域规则 ====================

/// 集中定义目标宽度的有效范围和默认值。
nonisolated enum ImageCompressionWidthRules {
    /// 目标宽度允许的最小正整数。
    static let minimum = 1

    /// 默认目标宽度，单位为像素。
    static let standard = 1_440

    /// 返回有效目标宽度；缺失或越界值由调用方决定如何回退。
    static func validated(_ value: Int?) -> Int? {
        guard let value, value >= minimum else {
            return nil
        }
        return value
    }
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

    /// 返回有效质量刻度；缺失或越界值由调用方决定如何回退。
    static func validated(_ value: Int?) -> Int? {
        guard let value, validValues.contains(value) else {
            return nil
        }
        return value
    }

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
        validatedMaximumWidth: ImageCompressionWidthRules.standard,
        validatedQuality: ImageCompressionQualityScale.standard
    )

    /// 输出允许达到的最大视觉宽度，单位为像素。
    let maximumWidth: Int

    /// 用户界面中的整数质量，范围为 `0...10`。
    let quality: Int

    /// ImageIO 接收的 `0.0...1.0` 线性压缩质量。
    var imageIOQuality: Double {
        ImageCompressionQualityScale.imageIOValue(for: quality)
    }

    /// 验证并创建一份压缩设置；无效输入不进入领域状态。
    init?(maximumWidth: Int, quality: Int) {
        guard
            let maximumWidth = ImageCompressionWidthRules.validated(
                maximumWidth
            ),
            let quality = ImageCompressionQualityScale.validated(quality)
        else {
            return nil
        }

        self.init(
            validatedMaximumWidth: maximumWidth,
            validatedQuality: quality
        )
    }

    /// 只接受本文件集中规则已经验证的两个字段。
    fileprivate init(validatedMaximumWidth: Int, validatedQuality: Int) {
        maximumWidth = validatedMaximumWidth
        quality = validatedQuality
    }

    /// 从独立持久化字段恢复设置，每个无效字段单独使用标准值。
    static func restoring(
        maximumWidth: Int?,
        quality: Int?
    ) -> ImageCompressionSettings {
        let maximumWidth = ImageCompressionWidthRules.validated(maximumWidth)
            ?? standard.maximumWidth
        let quality = ImageCompressionQualityScale.validated(quality)
            ?? standard.quality

        return ImageCompressionSettings(
            validatedMaximumWidth: maximumWidth,
            validatedQuality: quality
        )
    }
}

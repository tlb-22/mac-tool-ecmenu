/**
 根据图片原始尺寸、方向和目标宽度计算输出的视觉尺寸。
 集中表达保持比例及像素下限的缩放规则，供图像处理边界使用。
 */

import Foundation

/// 用方向修正后的视觉宽度限制输出，保持比例并至少保留一个像素高度。
nonisolated struct ImageCompressionDimensions: Equatable, Sendable {
    let width: Int
    let height: Int
    var thumbnailMaximumDimension: Int { max(width, height) }

    static func make(rawWidth: Int, rawHeight: Int, orientation: Int, maximumWidth: Int) -> Self {
        precondition(rawWidth > 0 && rawHeight > 0 && maximumWidth > 0)
        let swapsDimensions = (5...8).contains(orientation)
        let visualWidth = swapsDimensions ? rawHeight : rawWidth
        let visualHeight = swapsDimensions ? rawWidth : rawHeight
        let width = min(visualWidth, maximumWidth)
        let height = max(1, Int((Double(visualHeight) * Double(width) / Double(visualWidth)).rounded()))
        return Self(width: width, height: height)
    }
}

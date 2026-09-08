/**
 将图片、压缩参数和基准时间组织为确定顺序的批次计划。
 在执行前冻结逐项输出时间，实际图像处理与文件读写留在平台边界。
 */

import Foundation

/// 一张输入图片及其预定输出时间。
nonisolated struct ImageCompressionItemPlan: Equatable, Sendable {
    let sourceURL: URL
    let outputDate: Date
}

/// 已冻结设置、处理顺序和文件时间的批量计划。
nonisolated struct ImageCompressionPlan: Equatable, Sendable {
    let settings: ImageCompressionSettings
    let items: [ImageCompressionItemPlan]

    static func make(
        imageURLs: [URL],
        settings: ImageCompressionSettings,
        baseDate: Date
    ) -> ImageCompressionPlan {
        let sortedURLs = imageURLs.sorted { lhs, rhs in
            let nameOrder = lhs.lastPathComponent.localizedStandardCompare(
                rhs.lastPathComponent
            )
            if nameOrder == .orderedSame {
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
            return nameOrder == .orderedAscending
        }
        return ImageCompressionPlan(
            settings: settings,
            items: sortedURLs.enumerated().map { index, sourceURL in
                ImageCompressionItemPlan(
                    sourceURL: sourceURL,
                    outputDate: baseDate.addingTimeInterval(TimeInterval(index))
                )
            }
        )
    }
}

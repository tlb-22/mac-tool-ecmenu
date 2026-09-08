/**
 定义图像解码、尺寸处理与编码阶段可预期的处理失败。
 为系统处理边界提供稳定的错误阶段与诊断说明。
 */

import Foundation

/// ImageIO 无法用抛错 API 表达时使用的稳定功能错误。
nonisolated enum ImageCompressionProcessingError: LocalizedError {
    /// 选中的文件不能创建有效 ImageIO source。
    case invalidImageSource

    /// 容器没有可以处理的主图像或第一帧。
    case missingPrimaryImage

    /// ImageIO 没有提供计算目标尺寸所需的像素属性。
    case missingImageProperties

    /// ImageIO 无法生成带正确视觉方向的缩略图。
    case thumbnailCreationFailed

    /// Core Graphics 无法创建白色背景 RGB 输出位图。
    case bitmapCreationFailed

    /// ImageIO 无法创建或完成 JPEG 编码器。
    case jpegEncodingFailed

    /// 区分源读取与输出编码，供批量日志保留准确阶段。
    var stage: ImageCompressionSourceStage {
        switch self {
        case .invalidImageSource,
             .missingPrimaryImage,
             .missingImageProperties,
             .thumbnailCreationFailed:
            return .decode
        case .bitmapCreationFailed, .jpegEncodingFailed:
            return .encode
        }
    }

    /// 对应错误的稳定本地说明。
    var errorDescription: String? {
        switch self {
        case .invalidImageSource:
            return "无法读取图片容器。"
        case .missingPrimaryImage:
            return "图片容器中没有可处理的主图像。"
        case .missingImageProperties:
            return "无法读取图片像素尺寸。"
        case .thumbnailCreationFailed:
            return "无法按目标宽度解码图片。"
        case .bitmapCreationFailed:
            return "无法创建 JPG 使用的 RGB 图像。"
        case .jpegEncodingFailed:
            return "无法完成 JPG 编码。"
        }
    }
}

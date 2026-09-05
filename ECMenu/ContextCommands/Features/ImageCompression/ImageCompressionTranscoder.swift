import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

/// 使用系统图像能力，把一张源图片转换为独立 JPEG 数据。
nonisolated enum ImageCompressionTranscoder {
    /// 使用主图像、视觉方向和精确目标宽度生成无源元数据的 JPG 数据。
    static func encodedJPEG(
        from sourceURL: URL,
        settings: ImageCompressionSettings
    ) throws -> Data {
        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        try sourceHandle.close()

        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ImageCompressionProcessingError.invalidImageSource
        }

        let imageCount = CGImageSourceGetCount(source)
        guard imageCount > 0 else {
            throw ImageCompressionProcessingError.missingPrimaryImage
        }
        let reportedPrimaryIndex = CGImageSourceGetPrimaryImageIndex(source)
        let primaryIndex = (0..<imageCount).contains(reportedPrimaryIndex)
            ? reportedPrimaryIndex
            : 0
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                primaryIndex,
                nil
            ) as NSDictionary?,
            let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            rawWidth.intValue > 0,
            rawHeight.intValue > 0
        else {
            throw ImageCompressionProcessingError.missingImageProperties
        }

        let orientation = (
            properties[kCGImagePropertyOrientation] as? NSNumber
        )?.intValue ?? 1
        let swapsDimensions = (5...8).contains(orientation)
        let visualWidth = swapsDimensions
            ? rawHeight.intValue
            : rawWidth.intValue
        let visualHeight = swapsDimensions
            ? rawWidth.intValue
            : rawHeight.intValue
        let targetWidth = min(visualWidth, settings.maximumWidth)
        let targetHeight = max(
            1,
            Int(
                (
                    Double(visualHeight)
                        * Double(targetWidth)
                        / Double(visualWidth)
                ).rounded()
            )
        )
        let thumbnailMaximumDimension = max(targetWidth, targetHeight)

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaximumDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            primaryIndex,
            thumbnailOptions as CFDictionary
        ) else {
            throw ImageCompressionProcessingError.thumbnailCreationFailed
        }

        guard let outputImage = opaqueImage(
            from: thumbnail,
            width: targetWidth,
            height: targetHeight
        ) else {
            throw ImageCompressionProcessingError.bitmapCreationFailed
        }

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageCompressionProcessingError.jpegEncodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            outputImage,
            [
                kCGImageDestinationLossyCompressionQuality:
                    settings.imageIOQuality,
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressionProcessingError.jpegEncodingFailed
        }
        return encodedData as Data
    }

    /// 把方向已修正的图片高质量绘制到白底 sRGB 位图。
    private static func opaqueImage(
        from sourceImage: CGImage,
        width: Int,
        height: Int
    ) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return context.makeImage()
    }

}

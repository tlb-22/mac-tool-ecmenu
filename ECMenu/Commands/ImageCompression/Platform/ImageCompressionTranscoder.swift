/**
 通过 ImageIO 解码图片、按视觉尺寸缩放并编码 JPEG 数据。
 将底层图像 API 的失败转换为压缩领域可表达的处理错误。
 */

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
        let dimensions = ImageCompressionDimensions.make(
            rawWidth: rawWidth.intValue,
            rawHeight: rawHeight.intValue,
            orientation: orientation,
            maximumWidth: settings.maximumWidth
        )

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimensions.thumbnailMaximumDimension,
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
            width: dimensions.width,
            height: dimensions.height
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

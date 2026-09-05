import AppKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ECMenu

/// 通过真实源文件和输出验证图片转换的系统边界。
final class ImageCompressionBoundaryTests: XCTestCase {
    /// 目录拒绝创建输出时，报告保留源图与目录身份，并准确说明部分成功。
    func testDestinationWriteFailurePreservesImageIdentityAndOtherOutputs() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        let lockedDirectory = fixture.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: false)
        defer {
            _ = chflags(lockedDirectory.path, 0)
            try? FileManager.default.removeItem(at: fixture)
        }
        let rejectedURL = lockedDirectory.appendingPathComponent("rejected.png")
        let successfulURL = fixture.appendingPathComponent("success.png")
        try writeImage(makeImage(), to: rejectedURL, type: .png)
        try writeImage(makeImage(), to: successfulURL, type: .png)
        let sourceData = try Data(contentsOf: rejectedURL)
        XCTAssertEqual(chflags(lockedDirectory.path, UInt32(UF_IMMUTABLE)), 0)

        let report = await ImageCompressionExecution.execute(ImageCompressionPlan.make(
            imageURLs: [rejectedURL, successfulURL],
            settings: .standard,
            baseDate: Date()
        ))

        XCTAssertEqual(report.items.count, 2)
        XCTAssertEqual(report.outputURLs.map(\.lastPathComponent), ["success.jpg"])
        let failure = try XCTUnwrap(report.failures.first)
        guard case .destination(let sourceURL, let directoryURL, _) = failure else {
            return XCTFail("输出写入失败必须保留源图和目标目录")
        }
        XCTAssertEqual(sourceURL, rejectedURL)
        XCTAssertEqual(directoryURL, lockedDirectory)
        XCTAssertEqual(failure.kind, .permissionDenied)
        XCTAssertEqual(try Data(contentsOf: rejectedURL), sourceData)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rejectedURL.deletingPathExtension().appendingPathExtension("jpg").path
        ))
        XCTAssertEqual(
            try XCTUnwrap(ImageCompressionAlertContent.make(
                for: report,
                locale: Locale(identifier: "en")
            )).body,
            "Some images couldn’t be compressed because the folder containing “rejected.png” isn’t writable."
        )
    }

    /// 读取前失效的图片分类为 unavailable，后续图片仍完整转换。
    func testMissingSourceIsUnavailableAndDoesNotDiscardSuccess() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let missingURL = fixture.appendingPathComponent("missing.png")
        let sourceURL = fixture.appendingPathComponent("valid.png")
        try writeImage(makeImage(), to: sourceURL, type: .png)

        let report = await ImageCompressionExecution.execute(ImageCompressionPlan.make(
            imageURLs: [missingURL, sourceURL],
            settings: .standard,
            baseDate: Date()
        ))

        XCTAssertEqual(report.outputURLs.map(\.lastPathComponent), ["valid.jpg"])
        let failure = try XCTUnwrap(report.failures.first)
        guard case .source(let failedURL, .decode, _) = failure else {
            return XCTFail("失效输入应报告源读取失败")
        }
        XCTAssertEqual(failedURL, missingURL)
        XCTAssertEqual(failure.kind, .unavailable)
        XCTAssertNil(ImageCompressionAlertContent.make(for: report))
    }

    /// EXIF 5...8 的旋转与镜像必须作用于像素，目标宽度采用视觉方向。
    func testSwappedEXIFOrientationsTransformPixelsAndVisualWidth() throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let expectedCorners: [(Int, [RGB])] = [
            (5, [.red, .blue, .green, .yellow]),
            (6, [.blue, .red, .yellow, .green]),
            (7, [.yellow, .green, .blue, .red]),
            (8, [.green, .yellow, .red, .blue]),
        ]
        for (orientation, colors) in expectedCorners {
            let url = fixture.appendingPathComponent("orientation-\(orientation).jpg")
            try writeImage(makeImage(), to: url, type: .jpeg, properties: [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 1,
            ])
            let original = try source(at: url)
            XCTAssertEqual(
                try properties(of: original)[kCGImagePropertyOrientation] as? Int,
                orientation
            )
            let data = try ImageCompressionTranscoder.encodedJPEG(
                from: url,
                settings: try XCTUnwrap(ImageCompressionSettings(maximumWidth: 16, quality: 10))
            )
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, 16)
            XCTAssertEqual(bitmap.pixelsHigh, 32)
            for (index, point) in [(4, 8), (12, 8), (4, 24), (12, 24)].enumerated() {
                try assertColor(colors[index], at: point, in: bitmap)
            }
        }
    }

    /// GIF 只使用第一帧，小图重新编码但不放大。
    func testAnimatedGIFFirstFrameIsUsedWithoutUpscaling() throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("animated.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, 2, nil
        ))
        CGImageDestinationAddImage(destination, try makeImage(color: .red), nil)
        CGImageDestinationAddImage(destination, try makeImage(color: .blue), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertEqual(CGImageSourceGetCount(try source(at: url)), 2)

        let data = try ImageCompressionTranscoder.encodedJPEG(from: url, settings: .standard)
        let result = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(result), 1)
        XCTAssertEqual(CGImageSourceGetType(result) as String?, UTType.jpeg.identifier)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, 64)
        XCTAssertEqual(bitmap.pixelsHigh, 32)
        try assertColor(.red, at: (32, 16), in: bitmap)
    }

    /// 有明确主图像的 HEIC 容器按主图像生成单个输出。
    func testHEICUsesDeclaredPrimaryImage() throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("primary.heic")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.heic.identifier as CFString, 2, nil
        ))
        CGImageDestinationAddImage(destination, try makeImage(color: .red), [
            kCGImagePropertyPrimaryImage: false,
        ] as CFDictionary)
        CGImageDestinationAddImage(destination, try makeImage(color: .blue), [
            kCGImagePropertyPrimaryImage: true,
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = try source(at: url)
        XCTAssertEqual(CGImageSourceGetCount(original), 2)
        XCTAssertEqual(CGImageSourceGetPrimaryImageIndex(original), 1)

        let data = try ImageCompressionTranscoder.encodedJPEG(from: url, settings: .standard)
        let result = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(result), 1)
        try assertColor(.blue, at: (32, 16), in: XCTUnwrap(NSBitmapImageRep(data: data)))
    }

    /// 输出不能携带源图片的相机、拍摄时间、GPS 或自定义 XMP 信息。
    func testSourceMetadataIsNotCopiedIntoJPEG() throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("metadata.jpg")
        let marker = "ECMENU-PRIVATE-METADATA-MARKER"
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:ecmenu="https://example.invalid/ecmenu/" ecmenu:marker="\(marker)"/>
          </rdf:RDF>
        </x:xmpmeta>
        """
        let metadata = try XCTUnwrap(CGImageMetadataCreateFromXMPData(Data(xmp.utf8) as CFData))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImageAndMetadata(destination, try makeImage(), metadata, [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "ECMENU-CAMERA-MAKE",
                kCGImagePropertyTIFFModel: "ECMENU-CAMERA-MODEL",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2001:02:03 04:05:06",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 12.5,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 45.5,
                kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = try properties(of: source(at: url))
        XCTAssertNotNil(original[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(
            (original[kCGImagePropertyTIFFDictionary] as? NSDictionary)?[kCGImagePropertyTIFFMake] as? String,
            "ECMENU-CAMERA-MAKE"
        )
        XCTAssertEqual(
            (original[kCGImagePropertyExifDictionary] as? NSDictionary)?[kCGImagePropertyExifDateTimeOriginal] as? String,
            "2001:02:03 04:05:06"
        )
        XCTAssertNotNil(try Data(contentsOf: url).range(of: Data(marker.utf8)))

        let data = try ImageCompressionTranscoder.encodedJPEG(from: url, settings: .standard)
        let output = try properties(of: XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil)))
        XCTAssertNil(output[kCGImagePropertyGPSDictionary])
        XCTAssertNil((output[kCGImagePropertyTIFFDictionary] as? NSDictionary)?[kCGImagePropertyTIFFMake])
        XCTAssertNil((output[kCGImagePropertyTIFFDictionary] as? NSDictionary)?[kCGImagePropertyTIFFModel])
        XCTAssertNil((output[kCGImagePropertyExifDictionary] as? NSDictionary)?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertNil(data.range(of: Data(marker.utf8)))
    }

    private enum RGB {
        case red, green, blue, yellow

        var bytes: [UInt8] {
            switch self {
            case .red: [255, 0, 0, 255]
            case .green: [0, 255, 0, 255]
            case .blue: [0, 0, 255, 255]
            case .yellow: [255, 255, 0, 255]
            }
        }
    }

    /// 顶行红绿、底行蓝黄的像素布局可区分旋转和镜像。
    private func makeImage(color: RGB? = nil) throws -> CGImage {
        let width = 64
        let height = 32
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let quadrant: RGB = y < height / 2
                    ? (x < width / 2 ? .red : .green)
                    : (x < width / 2 ? .blue : .yellow)
                pixels.append(contentsOf: (color ?? quadrant).bytes)
            }
        }
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData)),
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func writeImage(
        _ image: CGImage,
        to url: URL,
        type: UTType,
        properties: [CFString: Any] = [:]
    ) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func source(at url: URL) throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    private func properties(of source: CGImageSource) throws -> NSDictionary {
        try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?)
    }

    private func assertColor(
        _ expected: RGB,
        at point: (Int, Int),
        in bitmap: NSBitmapImageRep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let color = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
        for (actual, byte) in zip(
            [color.redComponent, color.greenComponent, color.blueComponent],
            expected.bytes.prefix(3)
        ) {
            XCTAssertEqual(actual, CGFloat(byte) / 255, accuracy: 0.2, file: file, line: line)
        }
    }
}

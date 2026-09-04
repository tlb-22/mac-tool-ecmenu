import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum CompositionFailure: Error, CustomStringConvertible {
    case usage
    case outputDirectoryUnavailable(String)
    case imageUnreadable(String)
    case imageHasNoAlpha(String)
    case canvasUnavailable
    case outputUnavailable(String)
    case outputWriteFailed(String)

    var description: String {
        switch self {
        case .usage:
            "Usage: READMEOverviewComposer <output-directory> "
                + "<en-general> <en-context-menu> <en-finder-menu> "
                + "<zh-general> <zh-context-menu> <zh-finder-menu>"
        case let .outputDirectoryUnavailable(path):
            "Output directory is unavailable: \(path)"
        case let .imageUnreadable(path):
            "Could not read a source image: \(path)"
        case let .imageHasNoAlpha(path):
            "Source image has no alpha channel: \(path)"
        case .canvasUnavailable:
            "Could not create the overview image canvas."
        case let .outputUnavailable(path):
            "Could not create the overview image destination: \(path)"
        case let .outputWriteFailed(path):
            "Could not write the overview image: \(path)"
        }
    }
}

private struct SourceImage {
    let image: CGImage

    init(url: URL) throws {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CompositionFailure.imageUnreadable(url.path)
        }
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            break
        case .none, .noneSkipFirst, .noneSkipLast, .alphaOnly:
            throw CompositionFailure.imageHasNoAlpha(url.path)
        @unknown default:
            throw CompositionFailure.imageHasNoAlpha(url.path)
        }
        self.image = image
    }
}

/// README 总览图中具有固定顺序和显示权重的三列。
private enum OverviewColumn: CaseIterable {
    case generalSettings
    case contextMenuSettings
    case finderMenu

    /// Finder 菜单是产品主体，在总览图中使用更大的显示比例。
    var scale: CGFloat {
        switch self {
        case .generalSettings, .contextMenuSettings:
            1
        case .finderMenu:
            1.5
        }
    }
}

/// 一张来源图在最终画布上的明确像素尺寸。
private struct RenderedImage {
    let image: CGImage
    let width: Int
    let height: Int

    init(source: SourceImage, scale: CGFloat) {
        image = source.image
        width = Int((CGFloat(image.width) * scale).rounded())
        height = Int((CGFloat(image.height) * scale).rounded())
    }
}

private struct OverviewComposition {
    static let edgePadding = 64
    static let columnSpacing = 128

    let english: [SourceImage]
    let simplifiedChinese: [SourceImage]

    init(englishURLs: [URL], simplifiedChineseURLs: [URL]) throws {
        precondition(englishURLs.count == simplifiedChineseURLs.count)
        precondition(englishURLs.count == OverviewColumn.allCases.count)

        english = try englishURLs.map(SourceImage.init(url:))
        simplifiedChinese = try simplifiedChineseURLs.map(
            SourceImage.init(url:)
        )
    }

    func write(to outputDirectory: URL) throws {
        let english = renderedRow(from: english)
        let simplifiedChinese = renderedRow(from: simplifiedChinese)
        let rows = [english, simplifiedChinese]
        let columnWidths = english.indices.map { index in
            rows.map { $0[index].width }.max()!
        }
        let contentHeight = rows
            .flatMap { $0 }
            .map(\.height)
            .max()!
        let canvasWidth = Self.edgePadding * 2
            + columnWidths.reduce(0, +)
            + Self.columnSpacing * (columnWidths.count - 1)
        let canvasHeight = Self.edgePadding * 2 + contentHeight

        try write(
            row: english,
            columnWidths: columnWidths,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            contentHeight: contentHeight,
            to: outputDirectory.appendingPathComponent("overview-en.png")
        )
        try write(
            row: simplifiedChinese,
            columnWidths: columnWidths,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            contentHeight: contentHeight,
            to: outputDirectory.appendingPathComponent(
                "overview-zh-Hans.png"
            )
        )
    }

    /// 将语义列声明转换为每种语言共用的显示比例。
    private func renderedRow(
        from sources: [SourceImage]
    ) -> [RenderedImage] {
        zip(OverviewColumn.allCases, sources).map { pair in
            RenderedImage(source: pair.1, scale: pair.0.scale)
        }
    }

    private func write(
        row: [RenderedImage],
        columnWidths: [Int],
        canvasWidth: Int,
        canvasHeight: Int,
        contentHeight: Int,
        to outputURL: URL
    ) throws {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.displayP3),
            let context = CGContext(
                data: nil,
                width: canvasWidth,
                height: canvasHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw CompositionFailure.canvasUnavailable
        }

        context.clear(
            CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        )
        context.interpolationQuality = .high
        var columnX = Self.edgePadding
        for (index, source) in row.enumerated() {
            let image = source.image
            let imageX = columnX + (columnWidths[index] - source.width) / 2
            let imageY = Self.edgePadding
                + (contentHeight - source.height) / 2
            context.draw(
                image,
                in: CGRect(
                    x: imageX,
                    y: imageY,
                    width: source.width,
                    height: source.height
                )
            )
            columnX += columnWidths[index] + Self.columnSpacing
        }

        guard let outputImage = context.makeImage() else {
            throw CompositionFailure.canvasUnavailable
        }
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CompositionFailure.outputUnavailable(outputURL.path)
        }
        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CompositionFailure.outputWriteFailed(outputURL.path)
        }
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 7 else {
        throw CompositionFailure.usage
    }

    let outputDirectory = URL(fileURLWithPath: arguments[0])
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(
        atPath: outputDirectory.path,
        isDirectory: &isDirectory
    ), isDirectory.boolValue else {
        throw CompositionFailure.outputDirectoryUnavailable(
            outputDirectory.path
        )
    }

    let composition = try OverviewComposition(
        englishURLs: arguments[1...3].map(URL.init(fileURLWithPath:)),
        simplifiedChineseURLs: arguments[4...6].map(
            URL.init(fileURLWithPath:)
        )
    )
    try composition.write(to: outputDirectory)
} catch {
    let message = if let failure = error as? CompositionFailure {
        failure.description
    } else {
        error.localizedDescription
    }
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    Darwin.exit(EXIT_FAILURE)
}

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import EnhancedContextMenu

/// 验证压缩图片的纯计划和真实 ImageIO 输出。
final class ImageCompressionTests: XCTestCase {
    /// 正整数格式化器应允许清空替换，并在编辑阶段拒绝其他字符。
    func testPositiveIntegerFormatterInputRules() {
        let formatter = PositiveIntegerFormatter()

        for value in ["", "1", "1440"] {
            XCTAssertTrue(
                formatter.isPartialStringValid(
                    value,
                    newEditingString: nil,
                    errorDescription: nil
                ),
                "应接受：\(value)"
            )
        }

        for value in [
            "0",
            ".",
            "1.5",
            "-1",
            "+1",
            "abc",
            "1 2",
            "999999999999999999999999999999",
        ] {
            XCTAssertFalse(
                formatter.isPartialStringValid(
                    value,
                    newEditingString: nil,
                    errorDescription: nil
                ),
                "应拒绝：\(value)"
            )
        }

        var object: AnyObject?
        XCTAssertTrue(
            formatter.getObjectValue(
                &object,
                for: "1440",
                errorDescription: nil
            )
        )
        XCTAssertEqual((object as? NSNumber)?.intValue, 1_440)
    }

    /// 界面质量应线性映射，输入按 Finder 风格文件名排序并逐秒分配时间。
    func testSettingsAndPlanConstruction() {
        let settings = ImageCompressionSettings(
            maximumWidth: 1_440,
            quality: 8
        )
        XCTAssertEqual(settings.imageIOQuality, 0.8, accuracy: 0.000_001)

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = CompressImagesHandler.makePlan(
            imageURLs: [
                URL(fileURLWithPath: "/test/image10.png"),
                URL(fileURLWithPath: "/test/image2.png"),
                URL(fileURLWithPath: "/test/image1.png"),
            ],
            settings: settings,
            baseDate: baseDate
        )

        XCTAssertEqual(
            plan.items.map { $0.sourceURL.lastPathComponent },
            ["image1.png", "image2.png", "image10.png"]
        )
        XCTAssertEqual(
            plan.items.map(\.outputDate),
            [
                baseDate,
                baseDate.addingTimeInterval(1),
                baseDate.addingTimeInterval(2),
            ]
        )
    }

    /// 设置领域值应保留标准默认值，并覆盖 ImageIO 映射的两个端点。
    func testSettingsDefaultsAndQualityMapping() {
        XCTAssertEqual(
            ImageCompressionSettings.standard,
            ImageCompressionSettings(maximumWidth: 1_440, quality: 8)
        )
        XCTAssertEqual(
            ImageCompressionSettings(maximumWidth: 1, quality: 0)
                .imageIOQuality,
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ImageCompressionSettings(maximumWidth: 1, quality: 10)
                .imageIOQuality,
            1,
            accuracy: 0.000_001
        )
    }

    /// 注入的独立偏好套件应完整保存并恢复最后确认的设置。
    func testSettingsStoreRoundTrip() throws {
        let suiteName = "ImageCompressionTests.round-trip.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        let store = ImageCompressionSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .standard)

        let confirmed = ImageCompressionSettings(
            maximumWidth: 2_560,
            quality: 6
        )
        store.save(confirmed)

        XCTAssertEqual(store.load(), confirmed)
    }

    /// 无效持久化字段应各自回退默认值，不影响另一个仍有效的字段。
    func testSettingsStoreInvalidValuesFallBackIndependently() throws {
        let suiteName = "ImageCompressionTests.fallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        let store = ImageCompressionSettingsStore(defaults: defaults)

        defaults.set(900, forKey: ImageCompressionSettingsStore.maximumWidthKey)
        defaults.set(11, forKey: ImageCompressionSettingsStore.qualityKey)
        XCTAssertEqual(
            store.load(),
            ImageCompressionSettings(maximumWidth: 900, quality: 8)
        )

        defaults.set(0, forKey: ImageCompressionSettingsStore.maximumWidthKey)
        defaults.set(3, forKey: ImageCompressionSettingsStore.qualityKey)
        XCTAssertEqual(
            store.load(),
            ImageCompressionSettings(maximumWidth: 1_440, quality: 3)
        )
    }

    /// 第一张完成时请求取消，应保留完整输出且不开始处理第二张。
    @MainActor
    func testProgressCancellationStopsAtItemBoundary() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let firstSourceURL = fixture.appendingPathComponent("first.png")
        let secondSourceURL = fixture.appendingPathComponent("second.png")
        try writePNG(width: 4, height: 2, to: firstSourceURL)
        try writePNG(width: 4, height: 2, to: secondSourceURL)

        let requestID = UUID()
        var didRevealProgress = false
        var didRequestCancellation = false
        var renderedDescriptor: ContextCommandDescriptor?
        weak var centerReference: ContextCommandProgressCenter?
        let center = ContextCommandProgressCenter(
            displayDelay: .zero,
            render: { items in
                if !items.isEmpty {
                    didRevealProgress = true
                    renderedDescriptor = items.first?.descriptor
                }
                guard
                    !didRequestCancellation,
                    items.first?.completedUnitCount == 1
                else {
                    return
                }
                didRequestCancellation = true
                centerReference?.requestCancellation(requestID: requestID)
            }
        )
        centerReference = center
        let progress = ContextCommandProgressReporter(
            center: center,
            requestID: requestID,
            descriptor: CompressImagesCommand.descriptor
        )
        progress.begin(totalUnitCount: 2, allowsCancellation: true)
        for _ in 0..<100 where !didRevealProgress {
            await Task.yield()
        }
        XCTAssertTrue(didRevealProgress)

        let report = await CompressImagesHandler.execute(
            ImageCompressionPlan(
                maximumWidth: 4,
                imageIOQuality: 0.8,
                items: [
                    ImageCompressionItemPlan(
                        sourceURL: firstSourceURL,
                        outputDate: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                    ImageCompressionItemPlan(
                        sourceURL: secondSourceURL,
                        outputDate: Date(timeIntervalSince1970: 1_700_000_001)
                    ),
                ]
            ),
            progress: progress
        )
        progress.finish()

        XCTAssertTrue(report.wasCancelled)
        XCTAssertTrue(didRequestCancellation)
        XCTAssertEqual(renderedDescriptor, CompressImagesCommand.descriptor)
        XCTAssertEqual(
            report.outputURLs.map(\.lastPathComponent),
            ["first.jpg"]
        )
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.appendingPathComponent("second.jpg").path
            )
        )
    }

    /// 真实 PNG 应按视觉宽度缩小、编码为 JPG 并写入指定文件时间。
    func testImageIOCompressionAndFileDates() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let sourceURL = fixture.appendingPathComponent("wide.png")
        try writePNG(width: 8, height: 4, to: sourceURL)

        let outputDate = Date(timeIntervalSince1970: 1_700_000_000)
        let report = await CompressImagesHandler.execute(
            ImageCompressionPlan(
                maximumWidth: 4,
                imageIOQuality: 0.8,
                items: [
                    ImageCompressionItemPlan(
                        sourceURL: sourceURL,
                        outputDate: outputDate
                    ),
                ]
            )
        )

        XCTAssertTrue(report.issues.isEmpty)
        let outputURL = try XCTUnwrap(report.outputURLs.first)
        XCTAssertEqual(outputURL.lastPathComponent, "wide.jpg")
        let source = try XCTUnwrap(
            CGImageSourceCreateWithURL(outputURL as CFURL, nil)
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
        )
        XCTAssertEqual(
            (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            4
        )
        XCTAssertEqual(
            (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            2
        )

        let values = try outputURL.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey]
        )
        XCTAssertEqual(
            try XCTUnwrap(values.creationDate).timeIntervalSince1970,
            outputDate.timeIntervalSince1970,
            accuracy: 0.01
        )
        XCTAssertEqual(
            try XCTUnwrap(values.contentModificationDate).timeIntervalSince1970,
            outputDate.timeIntervalSince1970,
            accuracy: 0.01
        )
    }

    /// 两个并发批次争用 JPG 输出名时都不得覆盖源文件或彼此结果。
    func testJPEGSourceCollisionDoesNotOverwrite() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let sourceURL = fixture.appendingPathComponent("photo.jpg")
        try writeJPEG(width: 4, height: 2, to: sourceURL)
        let sourceData = try Data(contentsOf: sourceURL)

        let item = ImageCompressionItemPlan(
            sourceURL: sourceURL,
            outputDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let plan = ImageCompressionPlan(
            maximumWidth: 4,
            imageIOQuality: 0.8,
            items: [item]
        )
        let startBarrier = TwoTaskBarrier()
        let firstTask = Task.detached {
            await startBarrier.wait()
            return await CompressImagesHandler.execute(plan)
        }
        let secondTask = Task.detached {
            await startBarrier.wait()
            return await CompressImagesHandler.execute(plan)
        }
        let (firstReport, secondReport) = await (
            firstTask.value,
            secondTask.value
        )

        XCTAssertTrue(firstReport.issues.isEmpty)
        XCTAssertTrue(secondReport.issues.isEmpty)
        XCTAssertEqual(
            Set(
                (firstReport.outputURLs + secondReport.outputURLs)
                    .map(\.lastPathComponent)
            ),
            Set(["photo_copy.jpg", "photo_copy2.jpg"])
        )
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    /// 外部文件名使用最大可表示 copy 编号时仍应排他写入回退名称。
    func testMaximumCopyNumberWritesFallbackWithoutCrashing() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let stem = "photo_copy\(Int.max)"
        let sourceURL = fixture.appendingPathComponent("\(stem).jpg")
        try writeJPEG(width: 4, height: 2, to: sourceURL)
        let sourceData = try Data(contentsOf: sourceURL)
        let occupiedFallbackURL = fixture.appendingPathComponent(
            "\(stem)_copy.jpg"
        )
        let occupiedFallbackData = Data("occupied".utf8)
        try occupiedFallbackData.write(to: occupiedFallbackURL)

        let report = await CompressImagesHandler.execute(
            ImageCompressionPlan(
                maximumWidth: 4,
                imageIOQuality: 0.8,
                items: [
                    ImageCompressionItemPlan(
                        sourceURL: sourceURL,
                        outputDate: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ]
            )
        )

        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(
            report.outputURLs.map(\.lastPathComponent),
            ["\(stem)_copy2.jpg"]
        )
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertEqual(
            try Data(contentsOf: occupiedFallbackURL),
            occupiedFallbackData
        )
    }

    /// 带 Alpha 的输入应在 JPG 中合成到白色，而不是产生黑色背景。
    func testTransparentPixelsCompositeOnWhite() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let sourceURL = fixture.appendingPathComponent("transparent.png")
        try writeTransparentPNG(width: 2, height: 2, to: sourceURL)

        let report = await CompressImagesHandler.execute(
            ImageCompressionPlan(
                maximumWidth: 2,
                imageIOQuality: 1,
                items: [
                    ImageCompressionItemPlan(
                        sourceURL: sourceURL,
                        outputDate: Date(timeIntervalSince1970: 1_700_000_000)
                    ),
                ]
            )
        )
        let outputURL = try XCTUnwrap(report.outputURLs.first)
        let representation = try XCTUnwrap(
            NSBitmapImageRep(data: try Data(contentsOf: outputURL))
        )
        let sourceColor = try XCTUnwrap(
            representation.colorAt(x: 0, y: 0)
        )
        let color = try XCTUnwrap(
            sourceColor.usingColorSpace(NSColorSpace.sRGB)
        )
        XCTAssertGreaterThan(color.redComponent, 0.95)
        XCTAssertGreaterThan(color.greenComponent, 0.95)
        XCTAssertGreaterThan(color.blueComponent, 0.95)
    }

    /// 创建测试使用的纯色 PNG。
    private func writePNG(width: Int, height: Int, to url: URL) throws {
        try writeImage(
            width: width,
            height: height,
            type: UTType.png,
            to: url
        )
    }

    /// 创建像素完全透明的 PNG，用于验证 JPG 白底合成。
    private func writeTransparentPNG(
        width: Int,
        height: Int,
        to url: URL
    ) throws {
        let context = try XCTUnwrap(makeContext(width: width, height: height))
        try write(
            try XCTUnwrap(context.makeImage()),
            type: .png,
            to: url
        )
    }

    /// 创建测试使用的纯色 JPG。
    private func writeJPEG(width: Int, height: Int, to url: URL) throws {
        try writeImage(
            width: width,
            height: height,
            type: UTType.jpeg,
            to: url
        )
    }

    /// 通过 Core Graphics 和 ImageIO 写入指定尺寸的测试图片。
    private func writeImage(
        width: Int,
        height: Int,
        type: UTType,
        to url: URL
    ) throws {
        let context = try XCTUnwrap(makeContext(width: width, height: height))
        context.setFillColor(
            CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        try write(
            try XCTUnwrap(context.makeImage()),
            type: type,
            to: url
        )
    }

    /// 创建测试图片使用的透明 RGBA 位图上下文。
    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// 通过 ImageIO 写入一张测试图片。
    private func write(_ image: CGImage, type: UTType, to url: URL) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                type.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            image,
            nil
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

/// 让两个 detached 测试任务都就绪后再同时开始竞争目标名称。
private actor TwoTaskBarrier {
    /// 第一个到达并等待第二个任务的 continuation。
    private var firstWaiter: CheckedContinuation<Void, Never>?

    /// 第一个任务挂起，第二个任务到达时同时释放双方。
    func wait() async {
        if let firstWaiter {
            self.firstWaiter = nil
            firstWaiter.resume()
            return
        }

        await withCheckedContinuation { continuation in
            firstWaiter = continuation
        }
    }
}

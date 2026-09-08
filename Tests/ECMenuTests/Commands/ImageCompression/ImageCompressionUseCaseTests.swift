/**
 验证压缩用例在设置取消、单项编码失败及输出时间写入失败时的协调。
 注入处理边界检查继续执行与已生成结果保留，区分不同阶段的业务失败。
 */

import Darwin
import Foundation
import XCTest
@testable import ECMenu

final class ImageCompressionUseCaseTests: XCTestCase {
    /// 注入单项边界验证失败后继续、已生成输出保留，以及时间属性失败的独立语义。
    func testSourceFailureAndDateFailureDoNotDiscardCompletedOutput() async throws {
        let rejected = URL(fileURLWithPath: "/images/rejected.png")
        let accepted = URL(fileURLWithPath: "/images/accepted.png")
        let output = URL(fileURLWithPath: "/images/accepted.jpg")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let platform = ImageCompressionPlatform(
            encodedJPEG: { source, _ in
                if source == rejected { throw ImageCompressionProcessingError.jpegEncodingFailed }
                return Data([1, 2, 3])
            },
            writeJPEG: { data, source in
                XCTAssertEqual(source, accepted)
                XCTAssertEqual(data, Data([1, 2, 3]))
                return output
            },
            setFileDates: { url, outputDate in
                XCTAssertEqual(url, output)
                XCTAssertEqual(outputDate, date.addingTimeInterval(1))
                throw POSIXError(.EPERM)
            }
        )
        let report = await ImageCompressionExecution.execute(
            ImageCompressionPlan(settings: .standard, items: [
                ImageCompressionItemPlan(sourceURL: rejected, outputDate: date),
                ImageCompressionItemPlan(sourceURL: accepted, outputDate: date.addingTimeInterval(1)),
            ]),
            platform: platform
        )
        XCTAssertEqual(report.items.count, 2)
        XCTAssertEqual(report.outputURLs, [output])
        guard case .source(let source, .encode, _) = try XCTUnwrap(report.failures.first) else {
            return XCTFail("The encoding failure must retain its source stage")
        }
        XCTAssertEqual(source, rejected)
        XCTAssertEqual(report.outputs.first?.fileDateError?.code, Int(EPERM))
        XCTAssertTrue(report.hasIssues)
        XCTAssertFalse(report.wasCancelled)
    }

    /// 用户关闭参数窗口不进入系统处理，不产生任何输出或进度批次。
    @MainActor
    func testCancelledSettingsNeverStartImageProcessing() async throws {
        let handler = CompressImagesHandler(
            requestSettings: { nil },
            platform: ImageCompressionPlatform(
                encodedJPEG: { _, _ in
                    XCTFail("Cancelled settings cannot start decoding")
                    return Data()
                },
                writeJPEG: { _, url in
                    XCTFail("Cancelled settings cannot write output")
                    return url
                },
                setFileDates: { _, _ in XCTFail("Cancelled settings cannot set dates") }
            ),
            now: { Date(timeIntervalSince1970: 0) },
            present: { _, _ in XCTFail("Execution must not present feedback") }
        )
        let selection = try XCTUnwrap(FinderItemSelection(urls: [URL(fileURLWithPath: "/image.png")]))
        let result = await handler.execute(CompressImagesCommand(selection: selection))
        XCTAssertEqual(result, .cancelled)
    }
}

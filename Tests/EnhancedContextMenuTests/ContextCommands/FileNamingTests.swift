import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证不覆盖写入功能共用的文件冲突命名规则。
final class FileNamingTests: XCTestCase {
    /// 候选名称应使用无空格 `_copy2`，并延续已有 copy 序号。
    func testCollisionNaming() {
        let directory = URL(fileURLWithPath: "/test")
        let preferred = directory.appendingPathComponent("photo.jpg")
        XCTAssertEqual(
            Array(
                FileCollisionNaming.candidateURLs(for: preferred)
                    .prefix(4)
                    .map(\.lastPathComponent)
            ),
            ["photo.jpg", "photo_copy.jpg", "photo_copy2.jpg", "photo_copy3.jpg"]
        )

        let existingCopy = directory.appendingPathComponent("photo_copy2.jpg")
        XCTAssertEqual(
            Array(
                FileCollisionNaming.candidateURLs(for: existingCopy)
                    .prefix(3)
                    .map(\.lastPathComponent)
            ),
            ["photo_copy2.jpg", "photo_copy3.jpg", "photo_copy4.jpg"]
        )
    }

    /// 可表示编号耗尽后应保留完整原名，并从新的 `_copy` 序列继续。
    func testMaximumCopyNumberFallsBackToCompleteOriginalStem() {
        let directory = URL(fileURLWithPath: "/test")
        let maximum = directory.appendingPathComponent(
            "photo_copy\(Int.max).jpg"
        )
        XCTAssertEqual(
            Array(
                FileCollisionNaming.candidateURLs(for: maximum)
                    .prefix(3)
                    .map(\.lastPathComponent)
            ),
            [
                "photo_copy\(Int.max).jpg",
                "photo_copy\(Int.max)_copy.jpg",
                "photo_copy\(Int.max)_copy2.jpg",
            ]
        )

        let penultimate = directory.appendingPathComponent(
            "photo_copy\(Int.max - 1).jpg"
        )
        XCTAssertEqual(
            Array(
                FileCollisionNaming.candidateURLs(for: penultimate)
                    .prefix(4)
                    .map(\.lastPathComponent)
            ),
            [
                "photo_copy\(Int.max - 1).jpg",
                "photo_copy\(Int.max).jpg",
                "photo_copy\(Int.max - 1)_copy.jpg",
                "photo_copy\(Int.max - 1)_copy2.jpg",
            ]
        )

        let lowNumber = directory.appendingPathComponent("photo_copy2.jpg")
        XCTAssertEqual(
            FileCollisionNaming.candidateURL(
                for: lowNumber,
                sequenceNumber: Int.max
            ).lastPathComponent,
            "photo_copy2_copy.jpg"
        )
    }

    /// 超出整数表示范围的数字后缀应作为普通原名处理。
    func testUnrepresentableCopyNumberIsTreatedAsLiteralStem() {
        let directory = URL(fileURLWithPath: "/test")
        let digits = String(Int.max) + "0"
        let preferred = directory.appendingPathComponent(
            "photo_copy\(digits).jpg"
        )

        XCTAssertEqual(
            Array(
                FileCollisionNaming.candidateURLs(for: preferred)
                    .prefix(3)
                    .map(\.lastPathComponent)
            ),
            [
                "photo_copy\(digits).jpg",
                "photo_copy\(digits)_copy.jpg",
                "photo_copy\(digits)_copy2.jpg",
            ]
        )
    }
}

import Foundation
import XCTest
@testable import ECMenu

/// 验证底层 Cocoa 和 POSIX 错误可以归一化为稳定文件系统原因。
final class SystemErrorTests: XCTestCase {
    /// 各系统错误域中的常见可处理失败应映射到相同领域原因。
    func testFileSystemErrorClassification() {
        XCTAssertEqual(
            FileSystemErrorKind(
                classifying: SystemErrorSnapshot(
                    capturing: CocoaError(.fileWriteNoPermission)
                )
            ),
            .permissionDenied
        )
        XCTAssertEqual(
            FileSystemErrorKind(
                classifying: SystemErrorSnapshot(
                    capturing: POSIXError(.EROFS)
                )
            ),
            .readOnlyFileSystem
        )
        XCTAssertEqual(
            FileSystemErrorKind(
                classifying: SystemErrorSnapshot(
                    capturing: POSIXError(.ENOENT)
                )
            ),
            .unavailable
        )
    }

    /// Foundation 的通用路径错误与读取时缺失错误属于同一失效原因。
    func testCocoaMissingFileVariantsAreUnavailable() {
        for code in [CocoaError.Code.fileNoSuchFile, .fileReadNoSuchFile] {
            XCTAssertEqual(
                FileSystemErrorKind(classifying: SystemErrorSnapshot(
                    capturing: CocoaError(code)
                )),
                .unavailable
            )
        }
    }
}

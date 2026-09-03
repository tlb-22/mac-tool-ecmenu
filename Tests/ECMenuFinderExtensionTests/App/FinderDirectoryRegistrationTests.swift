import Foundation
import XCTest
@testable import ECMenuFinderExtension

/// 验证 Finder Sync 监听范围的标准化、去重和根目录回退规则。
final class FinderDirectoryRegistrationTests: XCTestCase {
    /// 系统卷枚举为空时，监听范围仍必须覆盖启动磁盘。
    func testRootFallback() {
        XCTAssertEqual(
            FinderSync.registeredDirectoryURLs(mountedVolumeURLs: []),
            [fileURL("/")]
        )
    }

    /// 文件卷根应标准化并去重，非文件 URL 不进入 Finder 范围。
    func testMountedVolumeRegistration() {
        let externalVolume = fileURL("/Volumes/External")
        let secondVolume = fileURL("/Volumes/Second")

        XCTAssertEqual(
            FinderSync.registeredDirectoryURLs(
                mountedVolumeURLs: [
                    fileURL("/"),
                    externalVolume,
                    fileURL("/Volumes/Other/../External"),
                    secondVolume,
                    URL(string: "https://example.com/not-a-volume")!,
                ]
            ),
            [fileURL("/"), externalVolume, secondVolume]
        )
    }

    /// 创建与生产代码相同形式的标准化目录文件 URL。
    private func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}

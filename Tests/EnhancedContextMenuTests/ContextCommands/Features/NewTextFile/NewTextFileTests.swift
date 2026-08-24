import Dispatch
import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证新建 TXT 的命名规则和真实文件系统执行。
final class NewTextFileTests: XCTestCase {
    /// 候选序列应完整、惰性并遵守产品命名顺序。
    func testCandidateNaming() {
        let directory = url("/test/parent")
        XCTAssertEqual(
            Array(
                CreateNewTextFileHandler
                    .candidateFileURLs(in: directory)
                    .prefix(3)
                    .map(\.lastPathComponent)
            ),
            ["untitled.txt", "untitled_copy.txt", "untitled_copy2.txt"]
        )
        XCTAssertEqual(
            CreateNewTextFileHandler.candidateFileURL(
                in: directory,
                sequenceNumber: Int.max
            ).lastPathComponent,
            "untitled_copy\(Int.max - 1).txt"
        )
    }

    /// 异步用例执行应创建空文件、保留命名顺序并分类失效目录。
    func testAsynchronousExecution() async throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let handler = CreateNewTextFileHandler()
        let directoryPath = try XCTUnwrap(AbsoluteFilePath(url: fixture))
        let command = CreateNewTextFileCommand(
            directoryPath: directoryPath
        )

        let first = try await handler.execute(command).get().fileURL
        let second = try CreateNewTextFileHandler.createEmptyTextFile(
            in: directoryPath
        )
        XCTAssertEqual(first.lastPathComponent, "untitled.txt")
        XCTAssertEqual(second.lastPathComponent, "untitled_copy.txt")
        XCTAssertTrue(try Data(contentsOf: first).isEmpty)
        XCTAssertTrue(try Data(contentsOf: second).isEmpty)

        let missingDirectory = fixture.appendingPathComponent("missing")
        let missingCommand = CreateNewTextFileCommand(
            directoryPath: try XCTUnwrap(
                AbsoluteFilePath(url: missingDirectory)
            )
        )
        guard case .failure(.directoryUnavailable(let url, let error)) = await handler.execute(
            missingCommand
        ) else {
            return XCTFail("A missing directory must produce directoryUnavailable")
        }
        XCTAssertEqual(url, missingDirectory)
        XCTAssertFalse(error.domain.isEmpty)
    }

    /// 同进程并发创建必须直接排他占用候选名，而不是先检查再写入。
    func testConcurrentCreationDoesNotOverwrite() throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let occupiedURL = fixture.appendingPathComponent("untitled.txt")
        let occupiedContents = Data("existing contents".utf8)
        try occupiedContents.write(to: occupiedURL)
        let results = ConcurrentCreationResults()
        let directoryPath = try XCTUnwrap(AbsoluteFilePath(url: fixture))

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            results.record(
                Result {
                    try CreateNewTextFileHandler.createEmptyTextFile(
                        in: directoryPath
                    )
                }
            )
        }

        let urls = try results.values()
        XCTAssertEqual(Set(urls).count, 8)
        XCTAssertFalse(urls.contains(occupiedURL))
        XCTAssertEqual(try Data(contentsOf: occupiedURL), occupiedContents)
        XCTAssertTrue(
            urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
        )
    }

    /// 创建标准化文件 URL。
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

/// 线程安全地收集并发文件创建结果。
private final class ConcurrentCreationResults: @unchecked Sendable {
    /// 保护结果数组的互斥锁。
    private let lock = NSLock()

    /// 每个并发创建任务返回的结果。
    private var results: [Result<URL, Error>] = []

    /// 在线程安全临界区内追加一个创建结果。
    func record(_ result: Result<URL, Error>) {
        lock.lock()
        results.append(result)
        lock.unlock()
    }

    /// 返回全部成功 URL，任一任务失败时重新抛出其错误。
    func values() throws -> [URL] {
        lock.lock()
        let snapshot = results
        lock.unlock()
        return try snapshot.map { try $0.get() }
    }
}

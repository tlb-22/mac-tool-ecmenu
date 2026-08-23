import Dispatch
import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证新建 TXT 的纯规划、命名规则和真实文件系统执行。
final class NewTextFileTests: XCTestCase {
    /// container、items 与 sidebar 使用各自已经解释完成的语义目标。
    func testFinderTargetResolution() {
        let parent = url("/test/parent")
        let child = url("/test/parent/child")
        let deepChild = url("/test/parent/child/grandchild/leaf")
        let siblingPrefix = url("/test/parent-other/child")
        let file = url("/test/parent/file.txt")
        let directories: Set<URL> = [parent, child, deepChild, siblingPrefix]

        XCTAssertEqual(
            resolve(.container(path: parent.path), directories)?.path,
            parent.path
        )
        XCTAssertEqual(
            resolve(.container(path: child.path), directories)?.path,
            child.path
        )
        XCTAssertEqual(
            resolve(.container(path: siblingPrefix.path), directories)?.path,
            siblingPrefix.path
        )
        XCTAssertEqual(
            resolve(items([child]), directories)?.path,
            child.path
        )
        XCTAssertEqual(
            resolve(items([file]), directories)?.path,
            parent.path
        )
        XCTAssertNil(
            resolve(items([file, child]), directories)
        )
        XCTAssertEqual(
            resolve(.sidebar(path: child.path), directories)?.path,
            child.path
        )
        XCTAssertNil(
            resolve(.sidebar(path: file.path), directories)
        )
    }

    /// 有效快照产生计划，含糊选择产生类型化目标失败。
    func testPlanConstruction() {
        let parent = url("/test/parent")
        let deepChild = url("/test/parent/child/grandchild")
        let containerSnapshot = FinderContextSnapshot.container(path: parent.path)

        XCTAssertEqual(
            try? CreateNewTextFileHandler.makePlan(
                for: containerSnapshot,
                directoryURLs: [parent, deepChild]
            ).get(),
            CreateNewTextFilePlan(directoryURL: parent)
        )

        let ambiguousSnapshot = items([parent, deepChild])
        guard case .failure(.targetUnavailable) = CreateNewTextFileHandler.makePlan(
            for: ambiguousSnapshot,
            directoryURLs: [parent, deepChild]
        ) else {
            return XCTFail("An ambiguous selection must produce targetUnavailable")
        }
    }

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
        let command = CreateNewTextFileCommand(
            finderContext: .container(path: fixture.path)
        )

        let first = try await handler.execute(command).get().fileURL
        let second = try CreateNewTextFileHandler.createEmptyTextFile(in: fixture)
        XCTAssertEqual(first.lastPathComponent, "untitled.txt")
        XCTAssertEqual(second.lastPathComponent, "untitled_copy.txt")
        XCTAssertTrue(try Data(contentsOf: first).isEmpty)
        XCTAssertTrue(try Data(contentsOf: second).isEmpty)

        let missingDirectory = fixture.appendingPathComponent("missing")
        let missingCommand = CreateNewTextFileCommand(
            finderContext: .container(path: missingDirectory.path)
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

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            results.record(
                Result {
                    try CreateNewTextFileHandler.createEmptyTextFile(in: fixture)
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

    /// 调用纯目标解析器，简化场景断言。
    private func resolve(
        _ snapshot: FinderContextSnapshot,
        _ directoryURLs: Set<URL>
    ) -> URL? {
        CreateNewTextFileHandler.targetDirectory(
            for: snapshot,
            directoryURLs: directoryURLs
        )
    }

    /// 创建标准化文件 URL。
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    /// 构造测试使用的非空 Finder 项目语义。
    private func items(_ urls: [URL]) -> FinderContextSnapshot {
        guard let selection = FinderItemSelection(urls: urls) else {
            preconditionFailure("A test item selection cannot be empty")
        }
        return .items(selection: selection)
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

import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证外部应用命令的单目标、目录类型、package 和符号链接语义。
final class OpenInApplicationTests: XCTestCase {
    /// VS Code 接受单个文件或目录，而 iTerm2 只接受单个目录。
    func testSingleSelectionRules() {
        let file = url("/test/file.swift")
        let directory = url("/test/folder")

        XCTAssertEqual(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [file],
                existingURLs: [file],
                directoryURLs: [],
                requiresDirectory: false
            ),
            file
        )
        XCTAssertNil(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [file],
                existingURLs: [file],
                directoryURLs: [],
                requiresDirectory: true
            )
        )
        XCTAssertEqual(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [directory],
                existingURLs: [directory],
                directoryURLs: [directory],
                requiresDirectory: true
            ),
            directory
        )
    }

    /// 多选无论类型组合如何都不产生外部应用目标。
    func testMultipleSelectionIsUnavailable() {
        let first = url("/test/first")
        let second = url("/test/second")

        XCTAssertNil(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [first, second],
                existingURLs: [first, second],
                directoryURLs: [first, second],
                requiresDirectory: false
            )
        )
    }

    /// 空白处优先采用当前容器，侧边栏采用被点击的目标目录。
    func testContainerAndSidebarDirectoryTargets() {
        let visibleDirectory = url("/test/parent")
        let staleDescendant = url("/test/parent/child")

        XCTAssertEqual(
            target(
                context: .container,
                targetedURL: staleDescendant,
                selectedURLs: [visibleDirectory],
                existingURLs: [visibleDirectory, staleDescendant],
                directoryURLs: [visibleDirectory, staleDescendant],
                requiresDirectory: true
            ),
            visibleDirectory
        )
        XCTAssertEqual(
            target(
                context: .sidebar,
                targetedURL: visibleDirectory,
                selectedURLs: [],
                existingURLs: [visibleDirectory],
                directoryURLs: [visibleDirectory],
                requiresDirectory: true
            ),
            visibleDirectory
        )
    }

    /// package 按目录处理；目录与文件链接按最终类型处理，断链不可用。
    func testFileSystemDirectorySemantics() throws {
        let fixture = try ProjectTestDirectory.makeUniqueDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let package = fixture.appendingPathComponent("Example.app")
        let directory = fixture.appendingPathComponent("folder")
        let directoryLink = fixture.appendingPathComponent("folder-link")
        let file = fixture.appendingPathComponent("script.sh")
        let fileLink = fixture.appendingPathComponent("script-link")
        let danglingLink = fixture.appendingPathComponent("dangling-link")
        try FileManager.default.createDirectory(
            at: package,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            at: directoryLink,
            withDestinationURL: directory
        )
        FileManager.default.createFile(atPath: file.path, contents: Data())
        try FileManager.default.createSymbolicLink(
            at: fileLink,
            withDestinationURL: file
        )
        try FileManager.default.createSymbolicLink(
            at: danglingLink,
            withDestinationURL: fixture.appendingPathComponent("missing")
        )

        let packageFacts = facts(for: [package])
        XCTAssertEqual(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [package],
                existingURLs: packageFacts.existing,
                directoryURLs: packageFacts.directories,
                requiresDirectory: true
            )?.path,
            package.standardizedFileURL.path
        )

        let linkFacts = facts(for: [directoryLink, danglingLink])
        XCTAssertEqual(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [directoryLink],
                existingURLs: linkFacts.existing,
                directoryURLs: linkFacts.directories,
                requiresDirectory: true
            )?.path,
            directoryLink.standardizedFileURL.path
        )
        XCTAssertNil(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [danglingLink],
                existingURLs: linkFacts.existing,
                directoryURLs: linkFacts.directories,
                requiresDirectory: false
            )
        )

        let fileLinkFacts = facts(for: [fileLink])
        XCTAssertEqual(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [fileLink],
                existingURLs: fileLinkFacts.existing,
                directoryURLs: fileLinkFacts.directories,
                requiresDirectory: false
            )?.path,
            fileLink.standardizedFileURL.path
        )
        XCTAssertNil(
            target(
                context: .items,
                targetedURL: nil,
                selectedURLs: [fileLink],
                existingURLs: fileLinkFacts.existing,
                directoryURLs: fileLinkFacts.directories,
                requiresDirectory: true
            )
        )
    }

    /// 应用不存在时，纯规划阶段返回明确的应用缺席失败。
    func testMissingApplicationFailsPlanning() {
        let targetURL = url("/test/file")
        let application = ContextCommandApplicationRequirement(
            bundleIdentifier: "test.missing.application",
            displayName: "Missing App"
        )

        XCTAssertEqual(
            OpenInApplicationExecution.makePlan(
                for: items([targetURL]),
                existingURLs: [targetURL],
                directoryURLs: [],
                application: application,
                applicationURL: nil,
                requiresDirectory: false
            ),
            .failure(.applicationUnavailable(application))
        )
    }

    /// 调用共享纯解析器，减少各测试中的快照构造噪音。
    private func target(
        context: FinderMenuContext,
        targetedURL: URL?,
        selectedURLs: [URL],
        existingURLs: Set<URL>,
        directoryURLs: Set<URL>,
        requiresDirectory: Bool
    ) -> URL? {
        guard let snapshot = semanticSnapshot(
            context: context,
            targetedURL: targetedURL,
            selectedURLs: selectedURLs
        ) else {
            return nil
        }
        return OpenInApplicationTargetResolver.targetURL(
            for: snapshot,
            existingURLs: existingURLs,
            directoryURLs: directoryURLs,
            requiresDirectory: requiresDirectory
        )
    }

    /// 把测试输入转换成共享模型允许表达的语义快照。
    private func semanticSnapshot(
        context: FinderMenuContext,
        targetedURL: URL?,
        selectedURLs: [URL]
    ) -> FinderContextSnapshot? {
        switch context {
        case .container:
            guard let url = selectedURLs.first ?? targetedURL else {
                return nil
            }
            return .container(path: url.standardizedFileURL.path)
        case .items:
            guard let selection = FinderItemSelection(urls: selectedURLs) else {
                return nil
            }
            return .items(selection: selection)
        case .sidebar:
            guard let url = targetedURL else {
                return nil
            }
            return .sidebar(path: url.standardizedFileURL.path)
        }
    }

    /// 用与生产边界相同的 FileManager 规则读取存在性和目录类型。
    private func facts(
        for urls: [URL]
    ) -> (existing: Set<URL>, directories: Set<URL>) {
        var existing: Set<URL> = []
        var directories: Set<URL> = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ) else {
                continue
            }
            let snapshotURL = URL(fileURLWithPath: url.path).standardizedFileURL
            existing.insert(snapshotURL)
            if isDirectory.boolValue {
                directories.insert(snapshotURL)
            }
        }
        return (existing, directories)
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

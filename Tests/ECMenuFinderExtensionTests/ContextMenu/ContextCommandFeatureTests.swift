import Darwin
import Foundation
import XCTest
@testable import ECMenuFinderExtension

/// 验证菜单期可见性与强类型命令参数由同一次求值产生。
@MainActor
final class ContextCommandFeatureTests: XCTestCase {
    /// 新建 TXT 应在菜单期把容器或单个文件解析为最终目录。
    func testNewTextFileResolvesTargetDirectory() throws {
        let fixture = try makeUniqueDirectory(purpose: "new-text-feature")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let fileURL = fixture.appendingPathComponent("selected.txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        let feature = CreateNewTextFileFeature(
            commandClient: ContextCommandClient()
        )

        XCTAssertEqual(
            feature.command(
                in: context(.container(path: try absolutePath(fixture)))
            )?.directoryPath,
            try absolutePath(fixture)
        )
        XCTAssertEqual(
            feature.command(in: context(try items([fileURL])))?.directoryPath,
            try absolutePath(fixture)
        )
        XCTAssertNil(
            feature.command(in: context(try items([fileURL, fixture])))
        )
        XCTAssertNil(
            feature.command(
                in: context(
                    .sidebar(path: try absolutePath(fileURL))
                )
            )
        )
    }

    /// 外部应用 Feature 应把单一目标和各自的目标种类固化到命令。
    func testOpenInApplicationBuildsTypedTarget() throws {
        let fixture = try makeUniqueDirectory(purpose: "open-feature")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let fileURL = fixture.appendingPathComponent("script.sh")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        let client = ContextCommandClient()
        let vscode = OpenInVSCodeFeature(commandClient: client)
        let iterm = OpenInITerm2Feature(commandClient: client)
        let fileContext = context(try items([fileURL]))
        let directoryContext = context(try items([fixture]))

        XCTAssertEqual(
            vscode.command(in: fileContext)?.targetPath,
            try absolutePath(fileURL)
        )
        XCTAssertNil(iterm.command(in: fileContext))
        XCTAssertEqual(
            iterm.command(in: directoryContext)?.targetPath,
            try absolutePath(fixture)
        )
        XCTAssertNil(
            vscode.command(in: context(try items([fileURL, fixture])))
        )
    }

    /// 外部应用菜单应按解析后的真实文件系统类型处理包与符号链接。
    func testOpenInApplicationHandlesPackagesAndSymbolicLinks() throws {
        let fixture = try makeUniqueDirectory(purpose: "open-link-feature")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let packageURL = fixture.appendingPathComponent(
            "Example.app",
            isDirectory: true
        )
        let directoryURL = fixture.appendingPathComponent(
            "directory",
            isDirectory: true
        )
        let fileURL = fixture.appendingPathComponent("file.txt")
        let directoryLinkURL = fixture.appendingPathComponent(
            "directory-link"
        )
        let fileLinkURL = fixture.appendingPathComponent("file-link")
        let brokenLinkURL = fixture.appendingPathComponent("broken-link")
        let missingURL = fixture.appendingPathComponent("missing-target")
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        try Data().write(to: fileURL)
        try FileManager.default.createSymbolicLink(
            at: directoryLinkURL,
            withDestinationURL: directoryURL
        )
        try FileManager.default.createSymbolicLink(
            at: fileLinkURL,
            withDestinationURL: fileURL
        )
        try FileManager.default.createSymbolicLink(
            at: brokenLinkURL,
            withDestinationURL: missingURL
        )

        let client = ContextCommandClient()
        let vscode = OpenInVSCodeFeature(commandClient: client)
        let iterm = OpenInITerm2Feature(commandClient: client)
        let cases: [(
            name: String,
            url: URL,
            vscodeAccepts: Bool,
            itermAccepts: Bool
        )] = [
            ("package", packageURL, true, true),
            ("directory symlink", directoryLinkURL, true, true),
            ("file symlink", fileLinkURL, true, false),
            ("broken symlink", brokenLinkURL, false, false),
        ]

        for testCase in cases {
            let targetPath = try absolutePath(testCase.url)
            let evaluationContext = context(try items([testCase.url]))
            XCTAssertEqual(
                vscode.command(in: evaluationContext)?.targetPath,
                testCase.vscodeAccepts ? targetPath : nil,
                testCase.name
            )
            XCTAssertEqual(
                iterm.command(in: evaluationContext)?.targetPath,
                testCase.itermAccepts ? targetPath : nil,
                testCase.name
            )
        }
    }

    /// 压缩命令只应携带全部受支持的非空图片选择。
    func testImageCompressionCarriesValidatedSelection() throws {
        let fixture = try makeUniqueDirectory(purpose: "compression-feature")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let imageURL = fixture.appendingPathComponent("image.png")
        let textURL = fixture.appendingPathComponent("notes.txt")
        try Data().write(to: imageURL)
        try Data().write(to: textURL)
        let feature = CompressImagesFeature(
            commandClient: ContextCommandClient()
        )
        let imageSelection = try selection([imageURL])

        XCTAssertEqual(
            feature.command(
                in: context(.items(selection: imageSelection))
            )?.selection,
            imageSelection
        )
        XCTAssertNil(
            feature.command(
                in: context(try items([imageURL, textURL]))
            )
        )
    }

    private func context(
        _ snapshot: FinderContextSnapshot
    ) -> FinderContextMenuEvaluationContext {
        FinderContextMenuEvaluationContext(snapshot: snapshot)
    }

    private func items(_ urls: [URL]) throws -> FinderContextSnapshot {
        .items(selection: try selection(urls))
    }

    private func selection(_ urls: [URL]) throws -> FinderItemSelection {
        try XCTUnwrap(FinderItemSelection(urls: urls))
    }

    private func absolutePath(_ url: URL) throws -> AbsoluteFilePath {
        try XCTUnwrap(AbsoluteFilePath(url: url))
    }

    /// 在项目内的单次测试目录中创建隔离 fixture。
    private func makeUniqueDirectory(purpose: String) throws -> URL {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let runDirectoryURL = projectRootURL
            .appendingPathComponent(
                ".artifacts/scratch/tests",
                isDirectory: true
            )
            .appendingPathComponent(
                "\(formatter.string(from: Date()))-\(purpose)-\(getpid())",
                isDirectory: true
            )
        let fixtureURL = runDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureURL,
            withIntermediateDirectories: true
        )
        return fixtureURL
    }
}

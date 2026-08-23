import Foundation
import XCTest
@testable import EnhancedContextMenu

/// 验证命令错误弹窗的纯文案合约，不触发真实 `NSAlert`。
final class CommandAlertContentTests: XCTestCase {
    /// 所有命令错误内容共用一个稳定标题。
    func testFixedTitle() {
        XCTAssertEqual(
            CommandAlertContent(body: "测试正文").title,
            "操作未完成"
        )
    }

    /// 权限不足和只读位置使用同一文案，且不暴露路径或系统诊断。
    func testNewTextFileUnifiesWritePermissionFailures() throws {
        let directoryURL = url("/private/test/secret/文稿")
        let error = diagnosticError()
        let permissionContent = try XCTUnwrap(
            CreateNewTextFileAlertContent.make(
                for: .permissionDenied(directoryURL, error)
            )
        )
        let readOnlyContent = try XCTUnwrap(
            CreateNewTextFileAlertContent.make(
                for: .readOnlyFileSystem(directoryURL, error)
            )
        )

        XCTAssertEqual(permissionContent, readOnlyContent)
        XCTAssertEqual(
            permissionContent,
            CommandAlertContent(
                body: "无法新建 TXT：“文稿”没有写入权限。"
            )
        )
        XCTAssertFalse(permissionContent.body.contains(directoryURL.path))
        XCTAssertFalse(permissionContent.body.contains(Self.diagnosticMarker))
    }

    /// 单项显示名称；批量中存在成功项时显示“部分”并按数量汇总。
    func testVisibilityUsesNamesCountsAndOperationScope() throws {
        let firstURL = url("/private/test/secret/first.txt")
        let secondURL = url("/private/test/secret/second.txt")
        let hideReport = VisibilityReport(
            succeededCount: 0,
            skippedDotItemCount: 0,
            issues: [
                visibilityIssue(at: firstURL, kind: .permissionDenied),
            ]
        )
        let showReport = VisibilityReport(
            succeededCount: 1,
            skippedDotItemCount: 0,
            issues: [
                visibilityIssue(at: firstURL, kind: .permissionDenied),
                visibilityIssue(at: secondURL, kind: .readOnlyFileSystem),
            ]
        )

        XCTAssertEqual(
            try XCTUnwrap(
                VisibilityAlertContent.make(
                    for: hideReport,
                    operation: .hide
                )
            ).body,
            "无法隐藏项目：“first.txt”没有写入权限。"
        )
        XCTAssertEqual(
            try XCTUnwrap(
                VisibilityAlertContent.make(
                    for: showReport,
                    operation: .show
                )
            ).body,
            "无法显示部分项目：2 个项目没有写入权限。"
        )
    }

    /// 压缩失败和文件时间问题分行且顺序稳定，多项写入问题按数量汇总。
    func testImageCompressionSeparatesIssueKindsAndCountsItems() throws {
        let sourceURL = url("/private/test/secret/a.png")
        let outputURL = url("/private/test/secret/b.jpg")
        let mixedReport = ImageCompressionReport(
            outputURLs: [outputURL],
            issues: [
                imageIssue(
                    at: sourceURL,
                    stage: .write,
                    kind: .permissionDenied
                ),
                imageIssue(
                    at: outputURL,
                    stage: .fileDates,
                    kind: .fileSystem
                ),
            ],
            wasCancelled: false
        )

        XCTAssertEqual(
            try XCTUnwrap(
                ImageCompressionAlertContent.make(for: mixedReport)
            ).body,
            "无法压缩部分图片：“a.png”没有写入权限。\n"
                + "部分图片已压缩但遇到问题：“b.jpg”的时间属性写入失败。"
        )

        let countedReport = ImageCompressionReport(
            outputURLs: [],
            issues: [
                imageIssue(
                    at: sourceURL,
                    stage: .decode,
                    kind: .permissionDenied
                ),
                imageIssue(
                    at: url("/private/test/secret/c.png"),
                    stage: .write,
                    kind: .readOnlyFileSystem
                ),
            ],
            wasCancelled: false
        )
        XCTAssertEqual(
            try XCTUnwrap(
                ImageCompressionAlertContent.make(for: countedReport)
            ).body,
            "无法压缩图片：2 张图片没有写入权限。"
        )
    }

    /// 文件时间问题是否为“部分”只取决于已经处理的其他图片。
    func testImageCompressionFileDateScopeUsesProcessedOutputs() throws {
        let datedOutputURL = url("/private/test/secret/dated.jpg")
        let onlyFileDateIssue = ImageCompressionReport(
            outputURLs: [datedOutputURL],
            issues: [
                imageIssue(
                    at: datedOutputURL,
                    stage: .fileDates,
                    kind: .permissionDenied
                ),
            ],
            wasCancelled: false
        )
        XCTAssertEqual(
            try XCTUnwrap(
                ImageCompressionAlertContent.make(for: onlyFileDateIssue)
            ).body,
            "图片已压缩但遇到问题：“dated.jpg”的时间属性写入失败。"
        )

        let cleanOutputURL = url("/private/test/secret/clean.jpg")
        let partialFileDateIssue = ImageCompressionReport(
            outputURLs: [cleanOutputURL, datedOutputURL],
            issues: [
                imageIssue(
                    at: datedOutputURL,
                    stage: .fileDates,
                    kind: .readOnlyFileSystem
                ),
            ],
            wasCancelled: false
        )
        XCTAssertEqual(
            try XCTUnwrap(
                ImageCompressionAlertContent.make(for: partialFileDateIssue)
            ).body,
            "部分图片已压缩但遇到问题：“dated.jpg”的时间属性写入失败。"
        )
    }

    /// 外部应用的各类失败只显示稳定命令文案，成功不产生错误内容。
    func testOpenInApplicationUsesStableCommandTextForEveryFailure() throws {
        let descriptors = [
            OpenInVSCodeCommand.descriptor,
            OpenInITerm2Command.descriptor,
        ]

        for descriptor in descriptors {
            let application = try XCTUnwrap(descriptor.requiredApplication)
            let plan = OpenInApplicationPlan(
                targetURL: url("/private/test/secret/project"),
                applicationURL: url("/Applications/\(application.displayName).app"),
                application: application
            )
            let failedOutcomes: [OpenInApplicationOutcome] = [
                .failed(.targetUnavailable),
                .failed(.applicationUnavailable(application)),
                .failed(.launchFailed(plan, diagnosticError())),
            ]
            let expected = CommandAlertContent(
                body: "无法\(descriptor.title)。"
            )

            for outcome in failedOutcomes {
                XCTAssertEqual(
                    OpenInApplicationAlertContent.make(
                        for: outcome,
                        commandTitle: descriptor.title
                    ),
                    expected
                )
            }
            XCTAssertNil(
                OpenInApplicationAlertContent.make(
                    for: .succeeded(plan),
                    commandTitle: descriptor.title
                )
            )
            XCTAssertFalse(expected.body.contains(plan.targetURL.path))
            XCTAssertFalse(expected.body.contains(Self.diagnosticMarker))
        }
    }

    private static let diagnosticMarker = "DIAGNOSTIC-MUST-NOT-APPEAR"

    /// 构造带有明确哨兵文字的底层错误快照。
    private func diagnosticError() -> SystemErrorSnapshot {
        SystemErrorSnapshot(
            capturing: NSError(
                domain: "CommandAlertContentTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: Self.diagnosticMarker,
                ]
            )
        )
    }

    /// 构造单项隐藏或显示问题。
    private func visibilityIssue(
        at url: URL,
        kind: VisibilityIssueKind
    ) -> VisibilityIssue {
        VisibilityIssue(
            itemURL: url,
            kind: kind,
            systemError: diagnosticError()
        )
    }

    /// 构造单项图片处理问题。
    private func imageIssue(
        at url: URL,
        stage: ImageCompressionIssueStage,
        kind: ImageCompressionIssueKind
    ) -> ImageCompressionIssue {
        ImageCompressionIssue(
            itemURL: url,
            stage: stage,
            kind: kind,
            systemError: diagnosticError()
        )
    }

    /// 构造标准化文件 URL。
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

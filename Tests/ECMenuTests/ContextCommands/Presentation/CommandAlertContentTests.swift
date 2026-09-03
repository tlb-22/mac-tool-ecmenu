import Foundation
import XCTest
@testable import ECMenu

/// 验证命令错误弹窗的纯文案合约，不触发真实 `NSAlert`。
final class CommandAlertContentTests: XCTestCase {
    private let english = Locale(identifier: "en")
    private let simplifiedChinese = Locale(identifier: "zh-Hans")

    /// 所有命令错误内容共用一个稳定标题。
    func testFixedTitle() {
        XCTAssertEqual(
            CommandAlertContent(body: "Test body", locale: english).title,
            "Operation Couldn’t Be Completed"
        )
        XCTAssertEqual(
            CommandAlertContent(
                body: "测试正文",
                locale: simplifiedChinese
            ).title,
            "操作未完成"
        )
    }

    /// 权限不足和只读位置使用同一文案，且不暴露路径或系统诊断。
    func testNewTextFileUnifiesWritePermissionFailures() throws {
        let directoryURL = url("/private/test/secret/文稿")
        let permissionContent = try XCTUnwrap(
            CreateNewTextFileAlertContent.make(
                for: CreateNewTextFileFailure(
                    directoryURL: directoryURL,
                    systemError: diagnosticError(kind: .permissionDenied)
                ),
                locale: simplifiedChinese
            )
        )
        let readOnlyContent = try XCTUnwrap(
            CreateNewTextFileAlertContent.make(
                for: CreateNewTextFileFailure(
                    directoryURL: directoryURL,
                    systemError: diagnosticError(kind: .readOnlyFileSystem)
                ),
                locale: simplifiedChinese
            )
        )

        XCTAssertEqual(permissionContent, readOnlyContent)
        XCTAssertEqual(
            permissionContent,
            CommandAlertContent(
                body: "无法新建 TXT：“文稿”没有写入权限。",
                locale: simplifiedChinese
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                CreateNewTextFileAlertContent.make(
                    for: CreateNewTextFileFailure(
                        directoryURL: directoryURL,
                        systemError: diagnosticError(kind: .permissionDenied)
                    ),
                    locale: english
                )
            ).body,
            "Couldn’t create a TXT file because “文稿” isn’t writable."
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
            issues: [
                visibilityIssue(at: firstURL, kind: .permissionDenied),
            ]
        )
        let showReport = VisibilityReport(
            succeededCount: 1,
            issues: [
                visibilityIssue(at: firstURL, kind: .permissionDenied),
                visibilityIssue(at: secondURL, kind: .readOnlyFileSystem),
            ]
        )

        XCTAssertEqual(
            try XCTUnwrap(
                VisibilityAlertContent.make(
                    for: hideReport,
                    operation: .hide,
                    locale: simplifiedChinese
                )
            ).body,
            "无法隐藏项目：“first.txt”没有写入权限。"
        )
        XCTAssertEqual(
            try XCTUnwrap(
                VisibilityAlertContent.make(
                    for: showReport,
                    operation: .show,
                    locale: simplifiedChinese
                )
            ).body,
            "无法显示部分项目：2 个项目没有写入权限。"
        )
        XCTAssertEqual(
            try XCTUnwrap(
                VisibilityAlertContent.make(
                    for: hideReport,
                    operation: .hide,
                    locale: english
                )
            ).body,
            "Couldn’t hide “first.txt” because it isn’t writable."
        )
        XCTAssertEqual(
            try XCTUnwrap(
                VisibilityAlertContent.make(
                    for: showReport,
                    operation: .show,
                    locale: english
                )
            ).body,
            "Some items couldn’t be shown because 2 items aren’t writable."
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
                    kind: .other
                ),
            ],
            wasCancelled: false
        )

        XCTAssertEqual(
            try XCTUnwrap(
                ImageCompressionAlertContent.make(
                    for: mixedReport,
                    locale: simplifiedChinese
                )
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
                ImageCompressionAlertContent.make(
                    for: countedReport,
                    locale: simplifiedChinese
                )
            ).body,
            "无法压缩图片：2 张图片没有写入权限。"
        )
        XCTAssertEqual(
            try XCTUnwrap(
                ImageCompressionAlertContent.make(
                    for: mixedReport,
                    locale: english
                )
            ).body,
            "Some images couldn’t be compressed because “a.png” isn’t writable.\n"
                + "Some images were compressed, but the date attributes of “b.jpg” couldn’t be updated."
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
                ImageCompressionAlertContent.make(
                    for: onlyFileDateIssue,
                    locale: simplifiedChinese
                )
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
                ImageCompressionAlertContent.make(
                    for: partialFileDateIssue,
                    locale: simplifiedChinese
                )
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
            let expectedChinese = CommandAlertContent(
                body: "无法进入 \(application.displayName)。",
                locale: simplifiedChinese
            )
            let expectedEnglish = CommandAlertContent(
                body: "Couldn’t open in \(application.displayName).",
                locale: english
            )

            for outcome in failedOutcomes {
                XCTAssertEqual(
                    OpenInApplicationAlertContent.make(
                        for: outcome,
                        applicationName: application.displayName,
                        locale: simplifiedChinese
                    ),
                    expectedChinese
                )
                XCTAssertEqual(
                    OpenInApplicationAlertContent.make(
                        for: outcome,
                        applicationName: application.displayName,
                        locale: english
                    ),
                    expectedEnglish
                )
            }
            XCTAssertNil(
                OpenInApplicationAlertContent.make(
                    for: .succeeded(plan),
                    applicationName: application.displayName,
                    locale: english
                )
            )
            XCTAssertFalse(expectedChinese.body.contains(plan.targetURL.path))
            XCTAssertFalse(expectedChinese.body.contains(Self.diagnosticMarker))
        }
    }

    private static let diagnosticMarker = "DIAGNOSTIC-MUST-NOT-APPEAR"

    /// 构造带有明确哨兵文字的底层错误快照。
    private func diagnosticError(
        kind: FileSystemErrorKind = .other
    ) -> SystemErrorSnapshot {
        let domain: String
        let code: Int
        switch kind {
        case .permissionDenied:
            domain = NSCocoaErrorDomain
            code = CocoaError.Code.fileWriteNoPermission.rawValue
        case .readOnlyFileSystem:
            domain = NSCocoaErrorDomain
            code = CocoaError.Code.fileWriteVolumeReadOnly.rawValue
        case .unavailable:
            domain = NSCocoaErrorDomain
            code = CocoaError.Code.fileNoSuchFile.rawValue
        case .other:
            domain = "CommandAlertContentTests"
            code = 1
        }
        return SystemErrorSnapshot(
            capturing: NSError(
                domain: domain,
                code: code,
                userInfo: [
                    NSLocalizedDescriptionKey: Self.diagnosticMarker,
                ]
            )
        )
    }

    /// 构造单项隐藏或显示问题。
    private func visibilityIssue(
        at url: URL,
        kind: FileSystemErrorKind
    ) -> VisibilityIssue {
        VisibilityIssue(
            itemURL: url,
            systemError: diagnosticError(kind: kind)
        )
    }

    /// 构造单项图片处理问题。
    private func imageIssue(
        at url: URL,
        stage: ImageCompressionIssueStage,
        kind: FileSystemErrorKind
    ) -> ImageCompressionIssue {
        ImageCompressionIssue(
            itemURL: url,
            stage: stage,
            systemError: diagnosticError(kind: kind)
        )
    }

    /// 构造标准化文件 URL。
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

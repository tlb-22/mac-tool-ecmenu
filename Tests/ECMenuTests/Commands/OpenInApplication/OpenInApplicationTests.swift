/**
 验证外部应用命令的目标约束、执行期重验与启动结果。
 以纯规则和注入的启动回调检查目标消失、应用缺失及原始路径保留。
 */

import Foundation
import XCTest
@testable import ECMenu

/// 验证外部应用命令的强类型目标约束和执行期重验。
final class OpenInApplicationTests: XCTestCase {
    /// VS Code 命令接受存在的文件，并把固定应用声明写入计划。
    func testVSCodeAcceptsExistingFile() throws {
        let targetPath = try absolutePath("/test/file.swift")
        let applicationURL = url("/Applications/Visual Studio Code.app")
        let command = OpenInVSCodeCommand(targetPath: targetPath)

        let plan = try OpenInApplicationRules.makePlan(
            for: command,
            targetState: .file,
            applicationURL: applicationURL
        ).get()

        XCTAssertEqual(plan.targetURL, targetPath.url)
        XCTAssertEqual(plan.applicationURL, applicationURL)
        XCTAssertEqual(
            plan.application,
            OpenInVSCodeCommand.applicationRequirement
        )
    }

    /// iTerm2 的目录约束由命令类型声明，执行期仍要重验。
    func testITermRejectsTargetThatBecameAFile() throws {
        let command = OpenInITerm2Command(
            targetPath: try absolutePath("/test/script.sh")
        )

        XCTAssertEqual(
            OpenInApplicationRules.makePlan(
                for: command,
                targetState: .file,
                applicationURL: url("/Applications/iTerm.app")
            ),
            .failure(.targetUnavailable)
        )
    }

    /// 菜单后消失的文件是真实外部变化，不由命令类型伪装成存在。
    func testTargetThatDisappearedFailsPlanning() throws {
        let command = OpenInVSCodeCommand(
            targetPath: try absolutePath("/test/missing")
        )

        XCTAssertEqual(
            OpenInApplicationRules.makePlan(
                for: command,
                targetState: .unavailable,
                applicationURL: url("/Applications/Visual Studio Code.app")
            ),
            .failure(.targetUnavailable)
        )
    }

    /// Launch Services 无法再定位应用时返回命令类型声明的应用。
    func testMissingApplicationFailsPlanning() throws {
        let command = OpenInVSCodeCommand(
            targetPath: try absolutePath("/test/file")
        )

        XCTAssertEqual(
            OpenInApplicationRules.makePlan(
                for: command,
                targetState: .file,
                applicationURL: nil
            ),
            .failure(
                .applicationUnavailable(
                    OpenInVSCodeCommand.applicationRequirement
                )
            )
        )
    }

    @MainActor
    func testLaunchCallbackFailureRetainsOriginalTargetAndApplication() async throws {
        let target = try absolutePath("/test/link")
        let appURL = url("/Applications/iTerm.app")
        var launchedPlan: OpenInApplicationPlan?
        let error = SystemErrorSnapshot(capturing: POSIXError(.EACCES))
        let handler = OpenInITerm2Handler(
            platform: OpenInApplicationPlatform(
                targetState: { _ in .directory },
                applicationURL: { _ in appURL },
                launch: { plan in
                    launchedPlan = plan
                    return .failed(.launchFailed(plan, error))
                }
            ),
            present: { _, _, _ in XCTFail("Execution must not present feedback") }
        )
        let result = await handler.execute(OpenInITerm2Command(targetPath: target))
        let plan = try XCTUnwrap(launchedPlan)
        XCTAssertEqual(plan.targetURL, target.url)
        XCTAssertEqual(plan.applicationURL, appURL)
        XCTAssertEqual(result, .failed(.launchFailed(plan, error)))
    }

    private func absolutePath(_ path: String) throws -> AbsoluteFilePath {
        try XCTUnwrap(AbsoluteFilePath(path: path))
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }
}

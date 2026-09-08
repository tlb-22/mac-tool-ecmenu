/**
 作为真实 Finder 菜单验收工具的单进程入口，执行权限检查、窗口枚举和截图请求。
 管理菜单会话、截图后校验与清理，并向调用脚本输出机器可读结果。
 */

import Darwin
import AppKit
import Foundation

/// 真实 Finder 菜单截图的单进程自动化入口。
@main
@MainActor
struct FinderMenuAutomationMain {
    static func main() async {
        do {
            let command = try CLICommand.parse(Array(CommandLine.arguments.dropFirst()))
            switch command {
            case .preflight:
                let permissions = PermissionReport.current(requestIfNeeded: true)
                ProtocolOutput.preflight(permissions)
                Darwin.exit(permissions.isReady ? EXIT_SUCCESS : EXIT_FAILURE)
            case .finderWindows:
                let permissions = PermissionReport.current()
                guard permissions.isReady else {
                    throw AutomationFailure.permissions(permissions)
                }
                ProtocolOutput.finderWindows(
                    try FinderWindowInventory.currentCount()
                )
                Darwin.exit(EXIT_SUCCESS)
            case let .capture(request):
                let permissions = PermissionReport.current()
                guard permissions.isReady else {
                    throw AutomationFailure.permissions(permissions)
                }
                _ = NSApplication.shared.setActivationPolicy(.accessory)
                NSApplication.shared.finishLaunching()
                await capture(request)
            }
        } catch let failure as AutomationFailure {
            ProtocolOutput.error(failure)
        } catch {
            ProtocolOutput.error(.unexpected(error.localizedDescription))
        }
        Darwin.exit(EXIT_FAILURE)
    }

    private static func capture(_ request: CLICommand.CaptureRequest) async -> Never {
        let session = FinderMenuSession(context: request.context)
        do {
            let rootMenu = try session.prepare()
            let capturedMenu: MenuSnapshot
            if let templateAction = request.templateAction {
                let submenu = try session.prepareTemplateSubmenu(
                    parentTitle: templateAction.parentTitle
                )
                capturedMenu = submenu.snapshot
                try await MenuScreenshot.capture(capturedMenu, to: request.outputURL)
                try session.verifyTemplateSubmenu(submenu)
                try session.performTemplate(
                    named: templateAction.templateTitle,
                    in: submenu,
                    expectedFileURL: templateAction.expectedFileURL
                )
                ProtocolOutput.line(
                    "CREATED\t\(Data(templateAction.expectedFileURL.path.utf8).base64EncodedString())"
                )
            } else {
                capturedMenu = rootMenu
                try await MenuScreenshot.capture(capturedMenu, to: request.outputURL)
                try session.verifyAfterCapture()
            }
            try session.closeOwnedUI()
            ProtocolOutput.captured(capturedMenu)
            Darwin.exit(EXIT_SUCCESS)
        } catch let primaryError {
            report(primaryError)
            do {
                try session.closeOwnedUI()
            } catch let cleanupError {
                report(cleanupError)
            }
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func report(_ error: Error) {
        if let failure = error as? AutomationFailure {
            ProtocolOutput.error(failure)
        } else {
            ProtocolOutput.error(.unexpected(error.localizedDescription))
        }
    }
}

private enum ProtocolOutput {
    static func preflight(_ report: PermissionReport) {
        line("PREFLIGHT\t\(report.accessibility ? 1 : 0)\t\(report.screenCapture ? 1 : 0)")
    }

    static func finderWindows(_ count: Int) {
        line("FINDER_WINDOWS\t\(count)")
    }

    static func captured(_ snapshot: MenuSnapshot) {
        for title in snapshot.titles where !title.isEmpty {
            line("ITEM\t\(Data(title.utf8).base64EncodedString())")
        }
        line("CAPTURED")
    }

    static func error(_ failure: AutomationFailure) {
        let message = Data(failure.message.utf8).base64EncodedString()
        line("ERROR\t\(failure.code)\t\(message)")
    }

    static func line(_ value: String) {
        FileHandle.standardOutput.write(Data("\(value)\n".utf8))
    }
}

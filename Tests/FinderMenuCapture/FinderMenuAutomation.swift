/**
 装配真实 Finder 菜单验收工具的权限检查、窗口枚举、通用截图与业务验收入口。
 管理菜单会话、截图后校验与清理，并向调用脚本输出机器可读结果。
 */

import Darwin
import AppKit
import Foundation

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
                guard permissions.isReady else { throw AutomationFailure.permissions(permissions) }
                ProtocolOutput.finderWindows(try FinderWindowInventory.currentCount())
                Darwin.exit(EXIT_SUCCESS)
            case let .capture(input, content):
                await capture(context: input.context) { session, rootMenu in
                    switch content {
                    case .menu:
                        try await MenuScreenshot.capture(rootMenu, to: input.outputURL)
                        try session.verifyAfterCapture()
                    case let .submenu(parentTitle):
                        let submenu = try session.prepareSubmenu(parentTitle: parentTitle)
                        try await MenuScreenshot.capture(
                            root: rootMenu, submenu: submenu.snapshot, to: input.outputURL
                        )
                        try session.verifySubmenu(submenu)
                    }
                    return rootMenu
                }
            case let .createFile(acceptance):
                await capture(context: acceptance.input.context) { session, _ in
                    let snapshot = try await acceptance.run(in: session)
                    ProtocolOutput.line(
                        "CREATED\t\(Data(acceptance.expectedFileURL.path.utf8).base64EncodedString())"
                    )
                    return snapshot
                }
            }
        } catch {
            report(error)
        }
        Darwin.exit(EXIT_FAILURE)
    }

    private static func capture(
        context: FinderMenuContext,
        operation: (FinderMenuSession, MenuSnapshot) async throws -> MenuSnapshot
    ) async -> Never {
        let session = FinderMenuSession(context: context)
        do {
            let permissions = PermissionReport.current()
            guard permissions.isReady else { throw AutomationFailure.permissions(permissions) }
            _ = NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.finishLaunching()
            let rootMenu = try session.prepare()
            let capturedMenu = try await operation(session, rootMenu)
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
        switch error {
        case AutomationFailure.usage:
            ProtocolOutput.error(code: "usage", message: CLICommand.usage)
        case let failure as AutomationFailure:
            ProtocolOutput.error(code: failure.code, message: failure.message)
        case let failure as NewFileMenuAcceptance.Failure:
            ProtocolOutput.error(code: failure.code, message: failure.message)
        default:
            let failure = AutomationFailure.unexpected(error.localizedDescription)
            ProtocolOutput.error(code: failure.code, message: failure.message)
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

    static func error(code: String, message: String) {
        let encodedMessage = Data(message.utf8).base64EncodedString()
        line("ERROR\t\(code)\t\(encodedMessage)")
    }

    static func line(_ value: String) {
        FileHandle.standardOutput.write(Data("\(value)\n".utf8))
    }
}

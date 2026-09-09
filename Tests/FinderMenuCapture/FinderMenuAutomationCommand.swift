/**
 定义 Finder 自动化工具支持的命令行操作，将参数交给通用捕获或具体能力验证。
 本文件是工具的操作装配入口，保留单一用法说明，不持有 Finder 会话或系统权限状态。
 */

import Foundation

enum CLICommand {
    case preflight
    case finderWindows
    case capture(FinderMenuCaptureInput, CaptureContent)
    case createFile(NewFileMenuAcceptance)

    enum CaptureContent {
        case menu
        case submenu(parentTitle: String)
    }

    static let usage = "Usage: FinderMenuAutomation preflight | finder-windows | container <output.png> <directory> | items <output.png> <item> [item ...] | submenu <output.png> <directory> <parent-title> | create-file <submenu.png> <directory> <parent-title> <template-title> <expected-file-name>"

    static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let command = arguments.first else { throw AutomationFailure.usage }
        switch command {
        case "preflight":
            guard arguments.count == 1 else { throw AutomationFailure.usage }
            return .preflight
        case "finder-windows":
            guard arguments.count == 1 else { throw AutomationFailure.usage }
            return .finderWindows
        case "container":
            guard arguments.count == 3 else { throw AutomationFailure.usage }
            return .capture(try .container(outputPath: arguments[1], directoryPath: arguments[2]), .menu)
        case "items":
            guard arguments.count >= 3 else { throw AutomationFailure.usage }
            return .capture(try .items(outputPath: arguments[1], firstPath: arguments[2], remainingPaths: Array(arguments.dropFirst(3))), .menu)
        case "submenu":
            guard arguments.count == 4, !arguments[3].isEmpty else { throw AutomationFailure.usage }
            return .capture(
                try .container(outputPath: arguments[1], directoryPath: arguments[2]),
                .submenu(parentTitle: arguments[3])
            )
        case "create-file":
            return .createFile(try NewFileMenuAcceptance.parse(arguments))
        default:
            throw AutomationFailure.usage
        }
    }
}

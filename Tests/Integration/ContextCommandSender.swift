/**
 提供独立签名进程，用真实生产 IPC 发送命令并查询菜单配置快照。
 解析集成验收参数，覆盖常驻主应用和按需唤醒场景中的认证传输边界。
 */

import Darwin
import Foundation

/// 使用与 Finder Extension 相同的真实代码签名身份验证生产 IPC。
@main
enum ContextCommandSender {
    private enum CommandMenuConfigOperation: String {
        case readOnce = "--menu-configuration"
        case waitForHost = "--wait-for-menu-configuration"
    }

    /// 解析测试场景，单次发送命令或查询菜单配置。
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.count == 1,
           let argument = arguments.first,
           let operation = CommandMenuConfigOperation(rawValue: argument) {
            try fetchCommandMenuConfig(operation)
            return
        }

        if arguments.count >= 2,
           let operation = arguments.first,
           ["--copy-path", "--hide-items", "--show-items"].contains(operation) {
            guard let selection = FinderItemSelection(
                paths: Array(arguments.dropFirst())
            ) else {
                throw SenderFailure(message: "Expected at least one absolute item path")
            }
            switch operation {
            case "--copy-path":
                guard let command = CopyPathCommand(
                    paths: selection.absolutePaths
                ) else {
                    throw SenderFailure(message: "Expected at least one absolute item path")
                }
                try deliver(command)
            case "--hide-items":
                try deliver(HideItemsCommand(selection: selection))
            case "--show-items":
                try deliver(ShowItemsCommand(selection: selection))
            default:
                preconditionFailure("Validated operation became unknown")
            }
            return
        }

        if arguments.count == 3, arguments[0] == "--new-file" {
            guard let uuid = UUID(uuidString: arguments[1]),
                  let directoryPath = AbsoluteFilePath(path: arguments[2]) else {
                throw SenderFailure(message: "Expected a template UUID and an absolute directory path")
            }
            try deliver(CreateNewFileCommand(
                directoryPath: directoryPath,
                templateID: FileTemplateID(rawValue: uuid)
            ))
            return
        }

        throw SenderFailure(
            message: "Expected --new-file TEMPLATE_UUID DIRECTORY, --menu-configuration, --wait-for-menu-configuration, or an item operation with absolute paths"
        )
    }

    /// 通过真实认证连接单次写入命令，不等待接管或业务结果。
    private static func deliver<Command: ContextCommandPayload>(
        _ command: Command
    ) throws {
        let request = try ContextCommandRequest(command: command)
        try makeClient().transmit(request)
        print("context-command sent")
    }

    /// 通过已验证 IPC 端点拉取菜单配置快照。
    private static func fetchCommandMenuConfig(_ operation: CommandMenuConfigOperation) throws {
        let configuration: CommandMenuConfigSnapshot
        switch operation {
        case .readOnce:
            configuration = try makeClient().fetchCommandMenuConfig()
        case .waitForHost:
            configuration = try waitForHostConfiguration()
        }
        let schemaVersion = CommandMenuConfigSnapshot.currentSchemaVersion
        print(
            "menu-configuration schema=\(schemaVersion) enabled=\(configuration.isEnabled)"
        )
        for template in configuration.newFileTemplates {
            print("template \(template.id.rawValue.uuidString) \(template.displayName)")
        }
    }

    /// 只读启动探测共用一个传输预算；只在端点尚不存在或尚无监听者时重试。
    private static func waitForHostConfiguration() throws -> CommandMenuConfigSnapshot {
        let deadline = LocalSocketDeadline(timeout: LocalSocketDeadline.defaultTimeout)
        while true {
            let remaining = try remainingInterval(until: deadline)
            do {
                return try makeClient(connectionTimeout: remaining).fetchCommandMenuConfig()
            } catch let error as ApplicationIPCError {
                guard case let .posix(operation, code) = error,
                      operation == "connect",
                      code == ENOENT || code == ECONNREFUSED else {
                    throw error
                }
                Thread.sleep(forTimeInterval: min(0.05, try remainingInterval(until: deadline)))
            }
        }
    }

    private static func remainingInterval(until deadline: LocalSocketDeadline) throws -> TimeInterval {
        let now = DispatchTime.now().uptimeNanoseconds
        guard deadline.dispatchTime.uptimeNanoseconds > now else {
            throw ApplicationIPCError.deadlineExceeded
        }
        return TimeInterval(deadline.dispatchTime.uptimeNanoseconds - now) / 1_000_000_000
    }

    /// 构造会验证精确主应用身份的真实 socket 客户端。
    private static func makeClient(
        connectionTimeout: TimeInterval = LocalSocketDeadline.defaultTimeout
    ) throws -> AuthenticatedLocalSocketClient {
        try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier,
            connectionTimeout: connectionTimeout
        )
    }

}

/// 表示集成测试入口的参数、传输、身份或配置响应失败。
private struct SenderFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

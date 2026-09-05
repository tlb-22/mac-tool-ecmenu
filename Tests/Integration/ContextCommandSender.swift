import Darwin
import Foundation

/// 使用与 Finder Extension 相同的真实代码签名身份验证生产 IPC。
@main
enum ContextCommandSender {
    private enum MenuConfigurationOperation: String {
        case readOnce = "--menu-configuration"
        case waitForHost = "--wait-for-menu-configuration"
    }

    /// 解析测试场景，单次发送命令或查询菜单配置。
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.count == 1,
           let argument = arguments.first,
           let operation = MenuConfigurationOperation(rawValue: argument) {
            try fetchMenuConfiguration(operation)
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

        if arguments.count == 1, let path = arguments.first {
            guard let directoryPath = AbsoluteFilePath(path: path) else {
                throw SenderFailure(message: "Expected an absolute directory path")
            }
            try deliver(
                CreateNewTextFileCommand(
                    directoryPath: directoryPath
                )
            )
            return
        }

        throw SenderFailure(
            message: "Expected DIRECTORY, --menu-configuration, --wait-for-menu-configuration, or an item operation with absolute paths"
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
    private static func fetchMenuConfiguration(_ operation: MenuConfigurationOperation) throws {
        let configuration: MenuConfiguration
        switch operation {
        case .readOnce:
            configuration = try makeClient().fetchMenuConfiguration()
        case .waitForHost:
            configuration = try waitForHostConfiguration()
        }
        let schemaVersion = MenuConfiguration.currentSchemaVersion
        print(
            "menu-configuration schema=\(schemaVersion) enabled=\(configuration.isEnabled)"
        )
    }

    /// 只读启动探测共用一个传输预算；只在端点尚不存在或尚无监听者时重试。
    private static func waitForHostConfiguration() throws -> MenuConfiguration {
        let deadline = LocalSocketDeadline(timeout: LocalSocketDeadline.defaultTimeout)
        while true {
            let remaining = try remainingInterval(until: deadline)
            do {
                return try makeClient(connectionTimeout: remaining).fetchMenuConfiguration()
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

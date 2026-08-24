import Foundation

/// 使用与 Finder Extension 相同的真实代码签名身份验证生产 IPC。
@main
enum ContextCommandSender {
    /// 解析测试场景，单次发送命令或查询菜单配置。
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments == ["--menu-configuration"] {
            try fetchMenuConfiguration()
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
            message: "Expected DIRECTORY, --menu-configuration, or an item operation with absolute paths"
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
    private static func fetchMenuConfiguration() throws {
        let configuration = try makeClient().fetchMenuConfiguration()
        let schemaVersion = MenuConfiguration.currentSchemaVersion
        print(
            "menu-configuration schema=\(schemaVersion) enabled=\(configuration.isEnabled)"
        )
    }

    /// 构造会验证精确主应用身份的真实 socket 客户端。
    private static func makeClient() throws -> AuthenticatedLocalSocketClient {
        try AuthenticatedLocalSocketClient(
            expectedServerSigningIdentifier:
                ApplicationIPC.applicationSigningIdentifier
        )
    }

}

/// 表示集成测试入口的参数、传输、身份或配置响应失败。
private struct SenderFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

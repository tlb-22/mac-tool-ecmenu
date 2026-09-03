import Foundation

/// 让共享 IPC 代码在 XCTest loader 中仍能定位实际承载它的产品 Bundle。
nonisolated private final class ApplicationIPCBundleToken {}

/// 主应用与 Finder Extension 共享的定向本地 IPC 常量。
nonisolated enum ApplicationIPC {
    /// 当前构建配置注入的 macOS Team-ID 风格 App Group。
    static let applicationGroupIdentifier = requiredInfoString(
        forKey: "ECMApplicationGroupIdentifier"
    )

    /// App Group 容器内的唯一 Unix-domain socket 叶名。
    static let socketName = "ipc"

    /// Finder Extension 校验主应用时要求的精确 signing identifier。
    static let applicationSigningIdentifier = requiredInfoString(
        forKey: "ECMApplicationSigningIdentifier"
    )

    /// 主应用校验 Finder Extension 时要求的精确 signing identifier。
    static let finderExtensionSigningIdentifier = requiredInfoString(
        forKey: "ECMFinderExtensionSigningIdentifier"
    )

    /// 通过系统 API 获取当前用户的 App Group 容器和 socket 路径。
    static func socketURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: applicationGroupIdentifier
        ) else {
            throw ApplicationIPCError.applicationGroupUnavailable
        }
        return containerURL.appendingPathComponent(
            socketName,
            isDirectory: false
        )
    }

    /// 从签名覆盖的构建产物 Info.plist 读取不可缺失的身份配置。
    private static func requiredInfoString(forKey key: String) -> String {
        let productBundle = Bundle(for: ApplicationIPCBundleToken.self)
        guard
            let value = productBundle.object(
                forInfoDictionaryKey: key
            ) as? String,
            !value.isEmpty,
            !value.contains("$(")
        else {
            preconditionFailure(
                "Missing or unresolved build identity value for \(key)"
            )
        }
        return value
    }
}

/// 一条已验证 Extension 连接可以提交给主应用的请求。
nonisolated enum ApplicationIPCRequest: Equatable, Sendable {
    /// 投递一次现有右键命令请求。
    case contextCommand(ContextCommandRequest)

    /// 获取主应用当前的菜单配置真相。
    case menuConfiguration
}

nonisolated extension ApplicationIPCRequest: Codable {
    /// 线上 JSON 中稳定的请求种类。
    private enum Kind: String, Codable {
        case contextCommand
        case menuConfiguration
    }

    /// 线上 JSON 的显式字段，避免依赖 Swift enum 的合成布局。
    private enum CodingKeys: String, CodingKey {
        case kind
        case contextCommand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .contextCommand:
            self = .contextCommand(
                try container.decode(
                    ContextCommandRequest.self,
                    forKey: .contextCommand
                )
            )
        case .menuConfiguration:
            guard !container.contains(.contextCommand) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .contextCommand,
                    in: container,
                    debugDescription: "Menu configuration request has a command payload"
                )
            }
            self = .menuConfiguration
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .contextCommand(request):
            try container.encode(Kind.contextCommand, forKey: .kind)
            try container.encode(request, forKey: .contextCommand)
        case .menuConfiguration:
            try container.encode(Kind.menuConfiguration, forKey: .kind)
        }
    }
}

/// IPC 建立、身份验证、framing 或编解码失败。
nonisolated enum ApplicationIPCError: Error, Equatable {
    case applicationGroupUnavailable
    case socketPathTooLong
    case socketPathOccupied
    case invalidSocketFile
    case peerAuditTokenLength(actual: Int, expected: Int)
    case peerTaskUnavailable
    case peerCodeRequirementMismatch
    case codeRequirement(operation: String, reason: String)
    case posix(operation: String, code: Int32)
    case connectionClosed
    case frameLengthOverflow
    case invalidAuthenticationReadyAcknowledgment
}

nonisolated extension ApplicationIPCError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .applicationGroupUnavailable:
            "The IPC App Group container is unavailable"
        case .socketPathTooLong:
            "The IPC socket path exceeds the platform limit"
        case .socketPathOccupied:
            "Another process already owns the IPC socket"
        case .invalidSocketFile:
            "The IPC path is occupied by a non-socket file"
        case let .peerAuditTokenLength(actual, expected):
            "The peer audit token has length \(actual), expected \(expected)"
        case .peerTaskUnavailable:
            "The peer audit token no longer identifies a running task"
        case .peerCodeRequirementMismatch:
            "The peer does not satisfy the required code-signing identity"
        case let .codeRequirement(operation, reason):
            "\(operation) failed: \(reason)"
        case let .posix(operation, code):
            "\(operation) failed with errno \(code)"
        case .connectionClosed:
            "The IPC connection closed before a complete message"
        case .frameLengthOverflow:
            "The IPC frame length cannot be represented by this process"
        case .invalidAuthenticationReadyAcknowledgment:
            "The IPC authentication-ready acknowledgment is invalid"
        }
    }
}

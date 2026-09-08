/**
 定义本地协议可承载的命令投递与命令菜单配置查询，并显式维护请求种类和 JSON 字段。
 编解码保留已发布的线上标识，按请求种类验证允许的负载组合。
 */

import Foundation

/// 一条已验证 Extension 连接可以提交给主应用的请求。
nonisolated enum ApplicationIPCRequest: Equatable, Sendable {
    /// 投递一次现有右键命令请求。
    case contextCommand(ContextCommandRequest)

    /// 获取主应用当前的菜单配置真相。
    case commandMenuSettings
}

nonisolated extension ApplicationIPCRequest: Codable {
    /// 线上 JSON 中稳定的请求种类。
    private enum Kind: String, Codable {
        case contextCommand
        case commandMenuSettings = "menuConfiguration"
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
        case .commandMenuSettings:
            guard !container.contains(.contextCommand) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .contextCommand,
                    in: container,
                    debugDescription: "Menu configuration request has a command payload"
                )
            }
            self = .commandMenuSettings
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .contextCommand(request):
            try container.encode(Kind.contextCommand, forKey: .kind)
            try container.encode(request, forKey: .contextCommand)
        case .commandMenuSettings:
            try container.encode(Kind.commandMenuSettings, forKey: .kind)
        }
    }
}

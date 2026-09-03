import Foundation

/// 对任意类型化右键命令进行 Codable 类型擦除的跨进程信封。
nonisolated struct ContextCommandEnvelope: Codable, Equatable, Sendable {
    /// 标识负载应由哪个类型化 Handler 解码。
    let featureID: ContextCommandFeatureID

    /// 由具体命令类型编码得到的原始 JSON 数据。
    private let payload: Data

    /// 把一个自描述的类型化命令封装为通用传输值。
    /// - Parameter command: Finder Feature 构造的具体命令参数。
    init<Command: ContextCommandPayload>(_ command: Command) throws {
        featureID = Command.descriptor.id
        payload = try JSONEncoder().encode(command)
    }

    /// 在稳定 ID 匹配时把原始负载恢复为指定命令类型。
    /// - Parameter commandType: 已注册 Handler 接受的命令类型。
    /// - Returns: 恢复后的类型化命令。
    func decode<Command: ContextCommandPayload>(
        as commandType: Command.Type
    ) throws -> Command {
        precondition(
            featureID == Command.descriptor.id,
            "A context-command payload was decoded as the wrong feature type"
        )
        return try JSONDecoder().decode(commandType, from: payload)
    }
}

/// 跨进程传输的一次右键命令请求。
nonisolated struct ContextCommandRequest: Codable, Equatable, Sendable {
    /// 主应用需要按稳定 ID 恢复的类型擦除命令。
    let command: ContextCommandEnvelope

    /// 创建新的命令请求。
    init(command: ContextCommandEnvelope) {
        self.command = command
    }

    /// 直接从类型化命令创建跨进程请求。
    /// - Parameter command: Finder Feature 构造的具体命令参数。
    init<Command: ContextCommandPayload>(command: Command) throws {
        self.init(
            command: try ContextCommandEnvelope(command)
        )
    }
}

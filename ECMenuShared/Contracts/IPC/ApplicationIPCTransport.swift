/**
 声明单向命令发送与菜单快照查询的异步调用边界，供生产传输和测试实现共同遵循。
 发送完成只表示请求已完整写出，查询成功交付有效快照；调用者通过结果处理实际传输失败。
 */

import Foundation

/// 允许生产客户端和测试替身共享单向命令发送边界。
nonisolated protocol ContextCommandSending: AnyObject, Sendable {
    /// 单次发送命令；成功只表示请求已完整写入经过验证的连接。
    func send(
        _ request: ContextCommandRequest,
        completion: @escaping @Sendable (
            Result<Void, Error>
        ) -> Void
    )
}

/// 允许生产客户端和测试替身共享菜单配置查询边界。
nonisolated protocol CommandMenuSettingsRequesting: AnyObject, Sendable {
    /// 从经过双向身份验证的连接取得主应用当前配置。
    func fetchCommandMenuSettings(
        completion: @escaping @Sendable (
            Result<CommandMenuSettingsSnapshot, Error>
        ) -> Void
    )
}


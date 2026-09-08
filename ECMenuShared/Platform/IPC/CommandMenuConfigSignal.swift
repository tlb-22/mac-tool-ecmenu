/**
 把命令菜单配置的变化提示适配为按构建身份区分的无正文分布式通知。
 接收端据此发起认证查询，权威快照通过定向连接传输；通知本身只提供重新读取的机会。
 */

import Foundation

/// 分布式通知只提示重新拉取，权威数据仍通过认证连接读取。
nonisolated extension CommandMenuConfigChannel {
    /// 主应用提示配置可能变化的无数据分布式通知。
    ///
    /// 该信号不携带任何权威数据；Extension 收到后必须通过双向身份验证的
    /// 定向 socket 重新拉取配置。
    static let didChangeNotification = Notification.Name(
        "\(ApplicationIPC.applicationSigningIdentifier).menu-configuration.did-change"
    )

    /// 只广播一次重新拉取提示，不发布配置正文。
    static func signalConfigurationChange() {
        DistributedNotificationCenter.default().postNotificationName(
            didChangeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

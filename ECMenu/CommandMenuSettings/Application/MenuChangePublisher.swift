/**
 提供主应用向菜单消费者发布配置失效提示的单一出口。
 以可注入通知操作连接业务提交与跨进程刷新提示。
 */

/// 菜单事实变更的发布出口；只提示副本重新读取，不持有另一份配置。
@MainActor
struct MenuChangePublisher {
    private let notify: () -> Void

    init(notify: @escaping () -> Void) {
        self.notify = notify
    }

    func signal() { notify() }
}

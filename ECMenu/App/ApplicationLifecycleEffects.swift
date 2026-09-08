/**
 声明应用生命周期需要的窗口、激活和 IPC 副作用，并解析首次打开事件的启动来源。
 以可注入操作连接生命周期决策与 AppKit，窗口实际状态由系统持有。
 */

import AppKit
import CoreServices

/// 首次 Open Application Apple Event 表达的进程启动来源。
enum ApplicationInitialOpenSource: Equatable {
    /// 用户或开发工具普通打开了主应用。
    case user

    /// Service Management 在用户登录后启动了主应用。
    case loginItem

    /// 只根据 Open Application 事件携带的登录项枚举恢复启动来源。
    /// - Parameter event: 首次 `kAEOpenApplication` 事件。
    init(openApplicationEvent event: NSAppleEventDescriptor) {
        let launchKind = event.paramDescriptor(
            forKeyword: keyAEPropData
        )?.enumCodeValue
        self = launchKind == keyAELaunchedAsLogInItem
            ? .loginItem
            : .user
    }
}

/// 生命周期的系统副作用；窗口的可见、最小化和业务窗口状态仍由 AppKit 持有。
@MainActor
struct ApplicationLifecycleEffects {
    let startIPC: () -> Void
    let changeActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    let showConfigurationWindow: () -> Void
    let closeConfigurationWindow: () -> Bool
    let closeActiveWindow: () -> Void
    let activate: () -> Void
}


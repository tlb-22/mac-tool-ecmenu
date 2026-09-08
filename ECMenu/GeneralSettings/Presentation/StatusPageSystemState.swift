/**
 保存配置界面一次刷新得到的扩展状态与已安装应用图标。
 从这些系统事实推导命令依赖是否可用，避免重复保存控件状态。
 */

import AppKit

/// 状态页一次读取后保留的系统事实，不保存可由这些事实推导的控件状态。
@MainActor
struct StatusPageSystemState {
    let isExtensionEnabled: Bool

    /// 系统可定位的应用及其图标；键的存在同时表示可用性。
    let applicationIcons: [String: NSImage]

    func isDependencyAvailable(for descriptor: ContextCommandDescriptor) -> Bool {
        descriptor.requiredApplication.map {
            applicationIcons[$0.bundleIdentifier] != nil
        } ?? true
    }
}


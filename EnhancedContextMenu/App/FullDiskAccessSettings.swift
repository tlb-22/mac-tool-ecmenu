import AppKit
import Foundation

/// 打开主应用“完全磁盘访问”系统设置页的单一平台适配器。
@MainActor
enum FullDiskAccessSettings {
    /// 通过系统工作区打开 macOS 13 及以后的
    /// “完全磁盘访问”设置入口。
    /// - Returns: 系统是否接受了打开请求。
    @discardableResult
    static func open() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}

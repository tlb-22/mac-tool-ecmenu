import Foundation

/// 从当前应用 Bundle 提供面向用户的稳定产品元数据。
@MainActor
enum ApplicationMetadata {
    /// 所有主应用界面共用的产品显示名称。
    static let displayName: String = {
        if
            let displayName = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleDisplayName"
            ) as? String,
            !displayName.isEmpty
        {
            return displayName
        }
        if
            let bundleName = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleName"
            ) as? String,
            !bundleName.isEmpty
        {
            return bundleName
        }
        return ProcessInfo.processInfo.processName
    }()

    /// 所有主应用界面共用的用户可见版本号。
    static let version: String = {
        guard
            let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            !version.isEmpty
        else {
            return "—"
        }
        return version
    }()
}

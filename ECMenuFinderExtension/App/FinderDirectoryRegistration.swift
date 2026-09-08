/**
 维护 Finder Sync 的观察范围，将卷枚举结果归一为包含系统根目录的完整管理集合。
 卷通知与延迟刷新由登记会话统一持有，实例释放时取消尚未执行的刷新并解除观察。
 */

import AppKit
import FinderSync
import OSLog

/// 拥有卷通知与合并刷新会话，维护 Finder Sync 的完整监听范围。
final class FinderDirectoryRegistration: NSObject {
    /// 卷挂载状态变化后等待系统完成更新的时间；不进入菜单 action 链路。
    private static let volumeRefreshDelay: TimeInterval = 1

    /// 记录 Finder 监听范围刷新，不在 Release 日志公开完整卷路径。
    private let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "FinderDirectoryScope"
    )

    /// 尚未执行的卷范围刷新，用于合并连续的挂载状态通知。
    private var pendingDirectoryRefresh: DispatchWorkItem?

    /// 主对象装配时启动范围登记；菜单请求不参与该生命周期。
    override init() {
        super.init()
        observeVolumeChanges()
        refreshDirectoryURLs(reason: "extension-startup")
    }

    deinit {
        pendingDirectoryRefresh?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - ==================== 副作用：读取并注册 Finder 目录范围 ====================

    /// 重新读取非隐藏挂载卷，并整体替换 Finder Sync 的监听根集合。
    /// - Parameter reason: 触发本次刷新的生命周期事件，仅用于诊断日志。
    private func refreshDirectoryURLs(reason: String) {
        let mountedVolumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        let directoryURLs = Self.registeredDirectoryURLs(
            mountedVolumeURLs: mountedVolumeURLs
        )

        FIFinderSyncController.default().directoryURLs = directoryURLs

        logger.info(
            "Registered \(directoryURLs.count) Finder directory roots after \(reason, privacy: .public)"
        )
        logger.debug(
            "Finder directory roots: \(directoryURLs.map(\.path).sorted().joined(separator: ", "), privacy: .private)"
        )
    }

    // MARK: - ==================== 纯函数：构造 Finder 监听范围 ====================

    /// 把系统根目录和文件 URL 形式的挂载卷根标准化、去重。
    /// - Parameter mountedVolumeURLs: 系统枚举得到的当前挂载卷根 URL。
    /// - Returns: 至少包含 `/` 的完整 Finder Sync 监听根集合。
    nonisolated static func registeredDirectoryURLs(
        mountedVolumeURLs: [URL]
    ) -> Set<URL> {
        let systemRootURL = URL(
            fileURLWithPath: "/",
            isDirectory: true
        ).standardizedFileURL
        let volumeURLs = mountedVolumeURLs.lazy
            .filter(\.isFileURL)
            .map(\.standardizedFileURL)

        return Set(volumeURLs).union([systemRootURL])
    }

    // MARK: - ==================== 副作用：响应卷生命周期 ====================

    /// 监听挂载、卸载和卷重命名，确保运行期间的监听范围保持最新。
    private func observeVolumeChanges() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let notificationNames: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]

        for notificationName in notificationNames {
            notificationCenter.addObserver(
                self,
                selector: #selector(handleVolumeChange(_:)),
                name: notificationName,
                object: nil
            )
        }
    }

    /// 合并连续卷通知，并在系统挂载状态稳定后刷新完整监听集合。
    /// - Parameter notification: `NSWorkspace` 发出的卷生命周期通知。
    @objc private func handleVolumeChange(_ notification: Notification) {
        pendingDirectoryRefresh?.cancel()

        let reason = notification.name.rawValue
        let refresh = DispatchWorkItem { [weak self] in
            self?.pendingDirectoryRefresh = nil
            self?.refreshDirectoryURLs(reason: reason)
        }
        pendingDirectoryRefresh = refresh
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.volumeRefreshDelay,
            execute: refresh
        )
    }
}

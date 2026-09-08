/**
 用上次确认的参数启动压缩设置交互，并保存新确认的参数。
 在恢复异步请求之前完成持久化，保持多个设置窗口的确认顺序。
 */

import Foundation

/// 管理最后确认的参数；确认通知先保存，再恢复请求，保留多个窗口的确认顺序。
@MainActor
struct ImageCompressionSettingsCoordinator {
    typealias Confirmation = @MainActor (ImageCompressionSettings) -> Void
    typealias Request = @MainActor (
        ImageCompressionSettings,
        @escaping Confirmation
    ) async -> ImageCompressionSettings?

    private let store: ImageCompressionSettingsStore
    private let request: Request

    init(store: ImageCompressionSettingsStore, request: @escaping Request) {
        self.store = store
        self.request = request
    }

    func requestSettings() async -> ImageCompressionSettings? {
        await request(store.load()) { settings in
            store.save(settings)
        }
    }
}

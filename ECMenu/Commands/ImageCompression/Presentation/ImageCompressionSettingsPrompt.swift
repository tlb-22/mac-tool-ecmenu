/**
 为每次压缩请求管理一个独立参数窗口，并把窗口操作桥接为异步结果。
 负责确认、关闭和任务取消时的窗口释放与请求恢复。
 */

import Foundation

/// 独立窗口与等待任务的一次性会话；不拥有持久化设置。
@MainActor
final class ImageCompressionSettingsPrompt {
    private let present: (ImageCompressionSettingsWindowController) -> Void
    private var activeControllers: [UUID: ImageCompressionSettingsWindowController] = [:]

    init(present: @escaping (ImageCompressionSettingsWindowController) -> Void) {
        self.present = present
    }

    /// 先同步发布确认值，再恢复等待者；关闭、取消和已取消 Task 都不发布确认。
    func request(
        settings: ImageCompressionSettings,
        onConfirm: @escaping @MainActor (ImageCompressionSettings) -> Void
    ) async -> ImageCompressionSettings? {
        let promptID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                let controller = ImageCompressionSettingsWindowController(settings: settings) { settings in
                    self.activeControllers[promptID] = nil
                    if let settings { onConfirm(settings) }
                    continuation.resume(returning: settings)
                }
                activeControllers[promptID] = controller
                present(controller)
            }
        } onCancel: {
            Task { @MainActor in
                self.activeControllers[promptID]?.dismiss()
            }
        }
    }
}

/**
 为图片选择贡献压缩菜单动作，并把通过输入判定的选择冻结为共享命令。
 菜单可用性依赖图片类型读取边界，参数交互与实际转换在主应用中执行。
 */

import Foundation

/// 压缩图片功能在 Finder Extension 中的可见性与命令发送端。
final class CompressImagesFeature: SingleActionContextMenuFeature {
    /// 为菜单身份和跨进程负载提供唯一的共享命令类型。
    typealias Command = CompressImagesCommand

    /// 向主应用投递压缩图片命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 注入跨进程命令客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    // MARK: - ==================== 副作用：读取选择集合的文件类型 ====================

    /// 仅为全部都是 ImageIO 支持图片的选择构造命令。
    func command(
        in context: FinderContextMenuEvaluationContext
    ) -> CompressImagesCommand? {
        guard case .items(let selection) = context.snapshot else {
            return nil
        }
        guard selection.urls.allSatisfy(ImageCompressionMenuInput.isSupportedImageFile) else {
            return nil
        }
        return CompressImagesCommand(selection: selection)
    }
}

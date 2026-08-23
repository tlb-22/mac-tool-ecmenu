import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 压缩图片功能在 Finder Extension 中的可见性与命令发送端。
final class CompressImagesFeature: SingleActionContextMenuFeature {
    /// 为菜单身份和跨进程负载提供唯一的共享命令类型。
    typealias Command = CompressImagesCommand

    /// 当前系统 ImageIO 声明支持的全部输入类型；进程内只构造一次。
    nonisolated private static let supportedSourceTypes: [UTType] = {
        let identifiers = CGImageSourceCopyTypeIdentifiers() as NSArray
        return identifiers.compactMap { identifier in
            guard let identifier = identifier as? String else {
                return nil
            }
            return UTType(identifier)
        }
    }()

    /// 向主应用投递压缩图片命令的通用客户端。
    let commandClient: ContextCommandClient

    /// 注入跨进程命令客户端。
    init(commandClient: ContextCommandClient) {
        self.commandClient = commandClient
    }

    // MARK: - ==================== 副作用：读取选择集合的文件类型 ====================

    /// 仅在全部选中对象都是 ImageIO 声明支持的图片文件时显示菜单。
    func isAvailable(in context: FinderContextMenuEvaluationContext) -> Bool {
        guard case .items(let selection) = context.snapshot else {
            return false
        }

        return selection.urls.allSatisfy(Self.isSupportedImageFile)
    }

    /// 读取单个 URL 的目录和内容类型，不在 Finder 菜单阶段解码图片。
    /// - Parameter url: Finder 当前选择的候选文件。
    /// - Returns: URL 是非目录且类型匹配 ImageIO 输入集合时为 `true`。
    nonisolated private static func isSupportedImageFile(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .contentTypeKey]
            ),
            values.isDirectory == false,
            let contentType = values.contentType,
            contentType != .pdf
        else {
            return false
        }

        return supportedSourceTypes.contains { supportedType in
            contentType == supportedType
                || contentType.conforms(to: supportedType)
        }
    }

    // MARK: - ==================== 纯函数：构造命令 ====================

    /// 使用当前菜单项在构建时绑定的 Finder 状态构造图片压缩命令。
    func command(for snapshot: FinderContextSnapshot) -> CompressImagesCommand {
        CompressImagesCommand(finderContext: snapshot)
    }
}

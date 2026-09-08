/**
 读取菜单判定所需的目录与内容类型事实，并与当前 ImageIO 支持的输入类型集合匹配。
 支持集合在进程内复用；选择项读取失败或类型不满足条件时返回不可用，菜单阶段只检查类型。
 */

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Finder 菜单阶段只查询内容类型与 ImageIO 支持集合，不解码图片。
nonisolated enum ImageCompressionMenuInput {
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

    /// 读取单个 URL 的目录和内容类型，不在 Finder 菜单阶段解码图片。
    /// - Parameter url: Finder 当前选择的候选文件。
    /// - Returns: URL 是非目录且类型匹配 ImageIO 输入集合时为 `true`。
    static func isSupportedImageFile(_ url: URL) -> Bool {
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
}

/**
 为主应用与 Finder Extension 提供同一套 macOS 文件类型图标查询。
 将文件名或后缀转换为系统内容类型；显示尺寸与图像缓存由调用端拥有。
 */

import AppKit
import UniformTypeIdentifiers

@MainActor
enum FileTypeIconProvider {
    static func icon(forFileName fileName: String) -> NSImage {
        let filenameExtension = (fileName as NSString).pathExtension
        return icon(forFilenameExtension: filenameExtension)
    }

    static func icon(forFilenameExtension filenameExtension: String) -> NSImage {
        let contentType = UTType(filenameExtension: filenameExtension) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }
}

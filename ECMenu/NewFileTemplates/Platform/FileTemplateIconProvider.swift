/**
 根据模板默认文件名的后缀取得 macOS 文件类型图标。
 将名称转换为系统内容类型并查询 NSWorkspace，图标由呈现层按需使用。
 */

import AppKit
import UniformTypeIdentifiers

@MainActor
enum FileTemplateIconProvider {
    static func icon(forFileName fileName: String) -> NSImage {
        let filenameExtension = (fileName as NSString).pathExtension
        let contentType = UTType(filenameExtension: filenameExtension) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }
}

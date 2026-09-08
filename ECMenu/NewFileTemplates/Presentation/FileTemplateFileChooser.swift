/**
 为导入与更换模板内容提供原生文件选择交互。
 封装 NSOpenPanel 的选择约束，向页面操作返回用户选择的文件 URL。
 */

import AppKit

/// 管理界面收集一个源文件选择；取消不产生存储操作。
@MainActor
enum FileTemplateFileChooser {
    static func chooseFile(title: LocalizedStringResource) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: title)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        let response = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
        guard response == .OK else { return nil }
        guard let url = panel.url else {
            preconditionFailure("An accepted open panel must provide its selected file")
        }
        return url
    }
}

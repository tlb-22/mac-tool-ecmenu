/**
 使用默认应用打开模板库中的内容副本。
 以 NSWorkspace 的同步布尔返回值判断打开请求是否成功，并提供失败说明。
 */

import AppKit

/// 请求默认应用打开模板副本，以系统返回值界定请求完成。
@MainActor
enum FileTemplateOpener {
    static func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw FileTemplateOpenError.couldNotOpen
        }
    }
}

private enum FileTemplateOpenError: LocalizedError {
    case couldNotOpen

    var errorDescription: String? {
        String(localized: "fileTemplates.error.open", defaultValue: "The template file could not be opened with its default application.")
    }
}

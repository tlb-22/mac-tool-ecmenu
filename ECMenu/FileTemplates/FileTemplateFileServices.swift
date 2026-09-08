import AppKit

/// 文件选择与默认应用打开的系统边界。
@MainActor
enum FileTemplateFileServices {
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

import Foundation

/// 模板库边界中真实可能发生的失败，保留操作类型和底层诊断。
nonisolated enum FileTemplateLibraryError: Error, Equatable, LocalizedError {
    case unsupportedFile(URL)
    case templateNotFound(FileTemplateID)
    case unsupportedSchema(Int)
    case invalidIndex(SystemErrorSnapshot)
    case fileOperation(FileTemplateFileOperation, url: URL, cause: SystemErrorSnapshot)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            String(localized: "Choose a regular file as the template.")
        case .templateNotFound:
            String(localized: "This file template no longer exists.")
        case .unsupportedSchema:
            String(localized: "The file template library uses an unsupported format.")
        case .invalidIndex:
            String(localized: "The file template library could not be read.")
        case .fileOperation(_, _, let cause):
            cause.localizedDescription
        }
    }
}

nonisolated enum FileTemplateFileOperation: Equatable, Sendable {
    case readIndex
    case prepareDirectory
    case readContent
    case saveContent
    case saveIndex
    case removeContent
}

/**
 根据源文件名和现有模板名称生成导入后的管理模型。
 身份由调用方显式传入，名称拆分与去重规则保持纯计算。
 */

import Foundation

/// 自动避重只发生在导入时，不限制用户随后手动保存的重复名称。
nonisolated enum FileTemplateImportNaming {
    static func template(
        id: FileTemplateID,
        from sourceURL: URL,
        existing: [FileTemplate]
    ) throws -> FileTemplate {
        let pathExtension = sourceURL.pathExtension
        let baseName = pathExtension.isEmpty ? sourceURL.lastPathComponent : pathExtension.uppercased()
        let usedNames = Set(existing.map(\.displayName))
        var displayName = baseName
        var suffix = 2
        while usedNames.contains(displayName) {
            displayName = "\(baseName) \(suffix)"
            suffix += 1
        }
        return try FileTemplate(
            id: id,
            displayName: displayName,
            defaultFileName: pathExtension.isEmpty ? "untitled" : "untitled.\(pathExtension)"
        )
    }
}

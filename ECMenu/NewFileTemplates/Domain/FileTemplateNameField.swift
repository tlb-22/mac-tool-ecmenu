/**
 标识模板中可编辑的名称字段，并应用单字段名称变更。
 将读取字段、验证新值与构造更新后模板的规则集中在领域层。
 */

import Foundation

/// 一次原地编辑只修改一个名称，另一个名称从最新已提交模板读取。
nonisolated enum FileTemplateNameField: Hashable, Sendable {
    case displayName
    case defaultFileName

    func value(in template: FileTemplate) -> String {
        switch self {
        case .displayName: template.displayName
        case .defaultFileName: template.defaultFileName
        }
    }

    func updating(_ template: FileTemplate, to value: String) throws -> FileTemplate {
        try FileTemplate(
            id: template.id,
            displayName: self == .displayName ? value : template.displayName,
            defaultFileName: self == .defaultFileName ? value : template.defaultFileName
        )
    }
}

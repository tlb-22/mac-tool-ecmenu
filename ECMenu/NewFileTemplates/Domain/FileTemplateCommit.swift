/**
 表达模板清单已经提交的结果，以及提交完成后可能出现的副本清理问题。
 将已生效的清单与后续清理诊断同时返回，供应用层发布和界面更新。
 */

import Foundation

/// 返回值只表示已经提交的事实；变更方法抛错只表示提交前失败。
nonisolated enum FileTemplateCommit: Equatable, Sendable {
    case committed([FileTemplate])
    case committedWithCleanupIssue([FileTemplate], FileTemplateCleanupIssue)

    var templates: [FileTemplate] {
        switch self {
        case .committed(let templates), .committedWithCleanupIssue(let templates, _):
            templates
        }
    }
}

/// 副本目录清理问题，只能描述删除副本这一种操作。
nonisolated struct FileTemplateCleanupIssue: Error, Equatable, Sendable, LocalizedError {
    let url: URL
    let cause: SystemErrorSnapshot

    var failure: FileTemplateLibraryError {
        .fileOperation(.removeContent, url: url, cause: cause)
    }

    var errorDescription: String? { cause.localizedDescription }
}

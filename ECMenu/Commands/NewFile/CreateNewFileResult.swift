/**
 表达新建文件的输出位置及模板读取、目标写入等失败结果。
 保留决定用户反馈所需的模板与文件事实。
 */

import Foundation

/// 文件创建完成后交给 Finder 反馈的不可变结果。
nonisolated struct CreateNewFileSuccess: Equatable, Sendable {
    let fileURL: URL
    let elapsedMilliseconds: UInt64
}

/// 模板读取与目标写入拥有不同的失败对象，不能混用权限文案。
nonisolated enum CreateNewFileFailure: Error, Equatable, Sendable {
    case template(FileTemplateID, SystemErrorSnapshot)
    case destination(directoryURL: URL, systemError: SystemErrorSnapshot)

    var systemError: SystemErrorSnapshot {
        switch self {
        case .template(_, let error), .destination(_, let error): error
        }
    }
}

typealias CreateNewFileOutcome = Result<CreateNewFileSuccess, CreateNewFileFailure>

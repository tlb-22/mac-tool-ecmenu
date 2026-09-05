import Foundation

/// 源图片尚未生成输出时可能失败的图像处理阶段。
nonisolated enum ImageCompressionSourceStage: String, Equatable, Sendable {
    case decode
    case encode
}

/// 没有生成输出的失败，明确区分受影响的图片与失败发生的位置。
nonisolated enum ImageCompressionFailure: Equatable, Sendable {
    case source(
        sourceURL: URL,
        stage: ImageCompressionSourceStage,
        error: SystemErrorSnapshot
    )
    case destination(
        sourceURL: URL,
        directoryURL: URL,
        error: SystemErrorSnapshot
    )

    /// 错误正文按图片汇总，始终引用源图片身份。
    var sourceURL: URL {
        switch self {
        case .source(let sourceURL, _, _), .destination(let sourceURL, _, _):
            sourceURL
        }
    }

    /// 诊断保留实际失败的源路径或目标目录。
    var locationURL: URL {
        switch self {
        case .source(let sourceURL, _, _): sourceURL
        case .destination(_, let directoryURL, _): directoryURL
        }
    }

    var systemError: SystemErrorSnapshot {
        switch self {
        case .source(_, _, let error), .destination(_, _, let error): error
        }
    }

    var kind: FileSystemErrorKind {
        FileSystemErrorKind(classifying: systemError)
    }

    /// 日志阶段由失败类型派生，不另存可与对象身份分歧的字段。
    var stageName: String {
        switch self {
        case .source(_, let stage, _): stage.rawValue
        case .destination: "write"
        }
    }
}

/// 已经完整写出的 JPG；时间属性失败不改变输出存在的事实。
nonisolated struct ImageCompressionOutput: Equatable, Sendable {
    let url: URL
    let fileDateError: SystemErrorSnapshot?
}

/// 一个输入到达终态时的唯一结果，不允许同时表达无输出失败与成功输出。
nonisolated enum ImageCompressionItemResult: Equatable, Sendable {
    case failed(ImageCompressionFailure)
    case output(ImageCompressionOutput)
}

/// 批次只保存逐项结果，反馈和 Finder 选择所需的集合按需派生。
nonisolated struct ImageCompressionReport: Equatable, Sendable {
    let items: [ImageCompressionItemResult]
    let wasCancelled: Bool

    var outputs: [ImageCompressionOutput] {
        items.compactMap {
            guard case .output(let output) = $0 else { return nil }
            return output
        }
    }

    var outputURLs: [URL] { outputs.map(\.url) }

    var failures: [ImageCompressionFailure] {
        items.compactMap {
            guard case .failed(let failure) = $0 else { return nil }
            return failure
        }
    }

    var hasIssues: Bool {
        items.contains {
            switch $0 {
            case .failed: true
            case .output(let output): output.fileDateError != nil
            }
        }
    }
}

/// 设置窗口取消与已经开始执行的批次保持不同的完成语义。
nonisolated enum ImageCompressionOutcome: Equatable, Sendable {
    case cancelled
    case completed(ImageCompressionReport)
}

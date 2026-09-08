/**
 在目标目录中以排他创建方式写入模板内容。
 仅在系统报告名称冲突时重试候选名称，其余写入失败直接交回调用方。
 */

import Foundation

extension NewFileWriter {
    nonisolated static var system: Self { Self(create: write) }

    /// 直接排他写入；只有系统报告名称冲突时继续候选序列。
    private nonisolated static func write(_ data: Data, preferredURL: URL) throws -> URL {
        for candidate in FileCollisionNaming.candidateURLs(for: preferredURL) {
            do {
                try data.write(to: candidate, options: .withoutOverwriting)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

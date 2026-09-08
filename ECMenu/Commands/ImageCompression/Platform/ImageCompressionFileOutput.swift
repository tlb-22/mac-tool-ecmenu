/**
 为压缩流程装配图像转换、JPEG 排他写入与文件时间设置的系统实现。
 按统一命名规则处理输出冲突，将写入和属性设置结果返回应用层。
 */

import Foundation

extension ImageCompressionPlatform {
    nonisolated static var system: Self {
        Self(
            encodedJPEG: ImageCompressionTranscoder.encodedJPEG,
            writeJPEG: writeJPEGWithoutOverwriting,
            setFileDates: { url, date in
                try FileManager.default.setAttributes(
                    [.creationDate: date, .modificationDate: date],
                    ofItemAtPath: url.path
                )
            }
        )
    }

    /// 编码结束后逐个排他尝试候选名，系统报告冲突时继续。
    private nonisolated static func writeJPEGWithoutOverwriting(
        _ data: Data,
        for sourceURL: URL
    ) throws -> URL {
        let preferredURL = sourceURL.deletingPathExtension().appendingPathExtension("jpg")
        for candidateURL in FileCollisionNaming.candidateURLs(for: preferredURL) {
            do {
                try data.write(to: candidateURL, options: .withoutOverwriting)
                return candidateURL
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

/**
 将模板元数据与一次读取取得的文件内容组成不可变值。
 为新建文件命令提供完整输入，避免暴露模板库的存储实现。
 */

import Foundation

/// 单次创建命令消费的不可变内容，不暴露内部库路径。
nonisolated struct FileTemplateContent: Equatable, Sendable {
    let template: FileTemplate
    let data: Data
}

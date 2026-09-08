/**
 定义模板管理页的加载中、可用与加载失败状态。
 让清单和错误随对应状态携带，供页面选择明确的展示分支。
 */

import Foundation

/// 模板库读取失败与有效空清单分别呈现。
enum FileTemplatePageState: Equatable {
    case loading
    case ready([FileTemplate])
    case failed(String)

    var templates: [FileTemplate]? {
        guard case .ready(let templates) = self else { return nil }
        return templates
    }
}

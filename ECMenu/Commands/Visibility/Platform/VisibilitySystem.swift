/**
 通过文件 URL 资源属性实现显示与隐藏的系统写入。
 将具体文件系统调用封装为可见性流程的可注入平台操作。
 */

import Foundation

extension VisibilityPlatform {
    nonisolated static var system: Self {
        Self(setHidden: { itemURL, isHidden in
            var values = URLResourceValues()
            values.isHidden = isHidden
            var mutableURL = itemURL
            try mutableURL.setResourceValues(values)
        })
    }
}

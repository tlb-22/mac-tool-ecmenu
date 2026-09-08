/**
 提供复制路径所需的文件存在性检查与一般剪贴板写入实现。
 将 lstat 文件对象检查和 NSPasteboard 写入封装为命令可注入的系统操作。
 */

import AppKit
import Darwin
import Foundation

extension CopyPathPlatform {
    nonisolated static var system: Self {
        Self(
            existingURLs: { paths in
                Set(paths.map(\.url).filter { url in
                    var information = stat()
                    return lstat(url.path, &information) == 0
                })
            },
            writeString: { value in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                return pasteboard.setString(value, forType: .string)
            }
        )
    }
}

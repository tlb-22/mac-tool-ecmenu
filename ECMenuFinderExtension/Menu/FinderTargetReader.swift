/**
 把文件系统的存在性和跟随符号链接后的目录判断适配为单目标菜单事实。
 读取只服务本次菜单可用性，权限与执行时目标变化由实际操作处理。
 */

import Foundation

/// 获取单目标菜单所需的文件系统种类；跟随符号链接。
nonisolated enum FinderTargetReader {
    /// 只读取存在性和目录类型，不预检写权限。
    static func read(at path: AbsoluteFilePath) -> FinderTargetKind? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: path.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }
        return isDirectory.boolValue ? .directory : .other
    }
}

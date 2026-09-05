import Foundation

/// 跟随符号链接后，单一 Finder 目标的文件系统种类。
nonisolated enum FinderTargetKind: Equatable, Sendable {
    case directory
    case other

    /// 只读取存在性和目录类型，不预检写权限。
    static func read(at path: AbsoluteFilePath) -> Self? {
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

/// 一次菜单构建读取的单目标事实；缺失目标和多选均不可供单目标命令使用。
nonisolated enum FinderSingleTargetFacts: Equatable, Sendable {
    case unavailable
    case existing(path: AbsoluteFilePath, kind: FinderTargetKind)
}

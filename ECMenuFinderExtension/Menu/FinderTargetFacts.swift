/**
 定义单目标菜单规则共用的文件种类与可用性事实，显式区分目录、其他对象和不可用目标。
 这些值承载一次读取的结果，使新建与外部应用能力共享观察而保持规则独立。
 */

import Foundation

/// 跟随符号链接后，单一 Finder 目标的文件系统种类。
nonisolated enum FinderTargetKind: Equatable, Sendable {
    case directory
    case other
}

/// 一次菜单构建读取的单目标事实；缺失目标和多选均不可供单目标命令使用。
nonisolated enum FinderSingleTargetFacts: Equatable, Sendable {
    case unavailable
    case existing(path: AbsoluteFilePath, kind: FinderTargetKind)
}

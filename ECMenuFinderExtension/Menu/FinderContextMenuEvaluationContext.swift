/**
 拥有单次同步菜单求值的语义快照与临时事实缓存，使相关能力复用同一份系统观察。
 缓存按事实类型区分，单目标读取边界可注入；其生命周期止于本次菜单构建。
 */

import Foundation

/// 一次 Finder 菜单构建独占的求值上下文。
///
/// Feature 可以在这里共享构建菜单所需的系统事实。实例只存活于本次同步
/// 渲染，不随 `NSMenuItem` 或 action 快照保留，因此不会把文件状态缓存到
/// 下一次右键菜单。
final class FinderContextMenuEvaluationContext {
    /// 本次菜单构建开始时冻结的 Finder 语义。
    let snapshot: FinderContextSnapshot

    /// 按事实值类型保存本次构建已经读取的结果。
    private var factsByType: [ObjectIdentifier: Any] = [:]

    /// 单目标命令共享的文件系统读取边界。
    private let readTargetKind: (AbsoluteFilePath) -> FinderTargetKind?

    /// 为一份冻结快照创建短生命周期求值上下文。
    /// - Parameter snapshot: 本次菜单实例唯一对应的 Finder 快照。
    init(
        snapshot: FinderContextSnapshot,
        readTargetKind: @escaping (AbsoluteFilePath) -> FinderTargetKind? =
            FinderTargetReader.read
    ) {
        self.snapshot = snapshot
        self.readTargetKind = readTargetKind
    }

    /// 同一菜单中的单目标命令复用存在性和种类，下次菜单重新读取。
    var singleTarget: FinderSingleTargetFacts {
        fact(FinderSingleTargetFacts.self) {
            let paths = snapshot.absolutePaths
            guard paths.count == 1,
                  let path = paths.first,
                  let kind = readTargetKind(path) else {
                return .unavailable
            }
            return .existing(path: path, kind: kind)
        }
    }

    /// 在本次菜单构建中至多读取一次指定类型的事实。
    /// - Parameters:
    ///   - type: 在一次构建中唯一标识这类事实的值类型。
    ///   - read: 尚无缓存时执行的同步系统事实读取。
    /// - Returns: 本次首次读取或随后复用的同一事实值。
    func fact<Fact>(
        _ type: Fact.Type,
        read: () -> Fact
    ) -> Fact {
        let key = ObjectIdentifier(type)
        if let cached = factsByType[key] {
            return cached as! Fact
        }

        let value = read()
        factsByType[key] = value
        return value
    }
}

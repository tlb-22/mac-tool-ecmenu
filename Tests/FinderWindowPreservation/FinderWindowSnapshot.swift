import Foundation

/// 解释窗口变化时使用的 Finder 进程事实；启动时间用于区分 PID 复用。
struct FinderWindowProcess: Codable, Hashable {
    let processIdentifier: Int32
    let launchTime: TimeInterval?
}

/// 无 GUI 会话与有 GUI 但没有 Finder 窗口是不同的观察结果。
enum FinderWindowSnapshot: Codable, Equatable {
    case noGUISession
    case desktop(processes: Set<FinderWindowProcess>, windowIDs: Set<UInt32>)
}

enum FinderWindowComparison: Equatable {
    case unchanged
    case skippedNoGUISession
    case guiSessionAppeared
    case guiSessionDisappeared
    case changed(added: Set<UInt32>, removed: Set<UInt32>)

    static func compare(
        before: FinderWindowSnapshot,
        after: FinderWindowSnapshot
    ) -> Self {
        switch (before, after) {
        case (.noGUISession, .noGUISession):
            return .skippedNoGUISession
        case (.noGUISession, .desktop):
            return .guiSessionAppeared
        case (.desktop, .noGUISession):
            return .guiSessionDisappeared
        case let (.desktop(_, beforeIDs), .desktop(_, afterIDs)):
            guard beforeIDs != afterIDs else { return .unchanged }
            return .changed(
                added: afterIDs.subtracting(beforeIDs),
                removed: beforeIDs.subtracting(afterIDs)
            )
        }
    }
}

/// 连续两次相同观察才能形成稳定快照；顺序变化不影响集合比较。
struct FinderWindowStability {
    private var previous: FinderWindowSnapshot?

    mutating func observe(_ snapshot: FinderWindowSnapshot) -> Bool {
        defer { previous = snapshot }
        return previous == snapshot
    }
}

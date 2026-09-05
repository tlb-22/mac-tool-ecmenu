import AppKit
import CoreGraphics
import Darwin
import Foundation

private enum WindowCheckFailure: Error, CustomStringConvertible {
    case usage
    case invalidWindowList
    case invalidWindowEntry
    case unstableSnapshot

    var description: String {
        switch self {
        case .usage:
            "Usage: FinderWindowCheck capture SNAPSHOT_FILE | verify SNAPSHOT_FILE AFTER_FILE"
        case .invalidWindowList:
            "WindowServer returned a window list with an unexpected representation."
        case .invalidWindowEntry:
            "WindowServer omitted a required window ID, owner PID, or layer."
        case .unstableSnapshot:
            "Finder window inventory did not stabilize within the observation budget."
        }
    }
}

@main
@MainActor
private enum FinderWindowCheck {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            switch arguments.first {
            case "capture" where arguments.count == 2:
                let observation = try settledSnapshot()
                try write(observation.snapshot, to: arguments[1])
                guard observation.isStable else { throw WindowCheckFailure.unstableSnapshot }
                if case .noGUISession = observation.snapshot {
                    print("SKIPPED\tNo Quartz GUI session or WindowServer is disabled.")
                } else {
                    print("CAPTURED\t\(describe(observation.snapshot))")
                }
            case "verify" where arguments.count == 3:
                let before = try JSONDecoder().decode(
                    FinderWindowSnapshot.self,
                    from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
                )
                let observation = try settledSnapshot(observeFullInterval: true)
                try write(observation.snapshot, to: arguments[2])
                let comparison = FinderWindowComparison.compare(
                    before: before,
                    after: observation.snapshot
                )
                guard observation.isStable else {
                    if case .changed = comparison {
                        reportDifference(comparison, before: before, after: observation.snapshot)
                    } else {
                        diagnostic("BEFORE\t\(describe(before))")
                        diagnostic("AFTER\t\(describe(observation.snapshot))")
                    }
                    throw WindowCheckFailure.unstableSnapshot
                }
                switch comparison {
                case .unchanged:
                    print("PASSED\tFinder window IDs unchanged.")
                case .skippedNoGUISession:
                    print("SKIPPED\tNo Quartz GUI session at either observation.")
                case .guiSessionAppeared, .guiSessionDisappeared, .changed:
                    reportDifference(comparison, before: before, after: observation.snapshot)
                    Darwin.exit(EXIT_FAILURE)
                }
            default:
                throw WindowCheckFailure.usage
            }
        } catch {
            diagnostic("ERROR\t\(error)")
            Darwin.exit(EXIT_FAILURE)
        }
    }

    /// CGWindow.h: optionAll 为零，包含屏幕内外窗口；nil 明确表示无 GUI 会话。
    /// 只读取必需元数据，不读取窗口标题，不截图，也不请求权限。
    private static func snapshot() throws -> FinderWindowSnapshot {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements],
            kCGNullWindowID
        ) else {
            return .noGUISession
        }
        guard let windows = windowList as? [[String: Any]] else {
            throw WindowCheckFailure.invalidWindowList
        }
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        )
        let processes = Set(applications.map {
            FinderWindowProcess(
                processIdentifier: $0.processIdentifier,
                launchTime: $0.launchDate?.timeIntervalSinceReferenceDate
            )
        })
        let processIDs = Set(processes.map(\.processIdentifier))
        var windowIDs: Set<UInt32> = []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let identifier = window[kCGWindowNumber as String] as? NSNumber else {
                throw WindowCheckFailure.invalidWindowEntry
            }
            if processIDs.contains(owner.int32Value), layer.int32Value == 0 {
                windowIDs.insert(identifier.uint32Value)
            }
        }
        return .desktop(processes: processes, windowIDs: windowIDs)
    }

    /// 验证固定采样十次，观察子进程结束后的异步窗口变化；捕获在两次一致后返回。
    private static func settledSnapshot(
        observeFullInterval: Bool = false
    ) throws -> (snapshot: FinderWindowSnapshot, isStable: Bool) {
        var stability = FinderWindowStability()
        for attempt in 0..<10 {
            let current = try snapshot()
            let isStable = stability.observe(current)
            if (isStable && !observeFullInterval) || attempt == 9 {
                return (current, isStable)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        preconditionFailure("The final sampling iteration always returns")
    }

    private static func write(_ snapshot: FinderWindowSnapshot, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func reportDifference(
        _ comparison: FinderWindowComparison,
        before: FinderWindowSnapshot,
        after: FinderWindowSnapshot
    ) {
        switch comparison {
        case let .changed(added, removed):
            diagnostic("FAILED\tFinder windows changed. Added IDs: \(added.sorted()); removed IDs: \(removed.sorted()).")
        case .guiSessionAppeared:
            diagnostic("FAILED\tA GUI session appeared after the baseline capture.")
        case .guiSessionDisappeared:
            diagnostic("FAILED\tThe baseline GUI session disappeared.")
        case .unchanged, .skippedNoGUISession:
            preconditionFailure("Only a changed observation is reported as a difference")
        }
        diagnostic("BEFORE\t\(describe(before))")
        diagnostic("AFTER\t\(describe(after))")
    }

    private static func describe(_ snapshot: FinderWindowSnapshot) -> String {
        switch snapshot {
        case .noGUISession:
            "no GUI session"
        case let .desktop(processes, windowIDs):
            "Finder processes=\(processes.sorted { $0.processIdentifier < $1.processIdentifier }); window IDs=\(windowIDs.sorted())"
        }
    }

    private static func diagnostic(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}

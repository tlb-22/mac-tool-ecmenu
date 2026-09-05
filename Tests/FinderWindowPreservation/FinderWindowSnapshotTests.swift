import Darwin
import Foundation

@main
private enum FinderWindowSnapshotTests {
    private static var passedCount = 0

    static func main() throws {
        expect(compare([10], [10, 20]) == .changed(added: [20], removed: []))
        expect(compare([10, 20], [10]) == .changed(added: [], removed: [20]))
        expect(compare([10, 20], [10, 30]) == .changed(added: [30], removed: [20]))
        expect(compare([10, 20], [20, 10]) == .unchanged)
        expect(compare([], []) == .unchanged)

        let baseline = desktop([10])
        let transient = desktop([10, 20])
        var stability = FinderWindowStability()
        expect(!stability.observe(baseline))
        expect(!stability.observe(transient))
        expect(!stability.observe(baseline))
        expect(stability.observe(baseline))
        expect(FinderWindowComparison.compare(before: baseline, after: baseline) == .unchanged)

        expect(FinderWindowComparison.compare(
            before: .noGUISession,
            after: .noGUISession
        ) == .skippedNoGUISession)
        expect(FinderWindowComparison.compare(
            before: baseline,
            after: .noGUISession
        ) == .guiSessionDisappeared)
        expect(FinderWindowComparison.compare(
            before: .noGUISession,
            after: desktop([])
        ) == .guiSessionAppeared)

        let restarted = desktop([30], pid: 2, launchTime: 200)
        expect(FinderWindowComparison.compare(
            before: baseline,
            after: restarted
        ) == .changed(added: [30], removed: [10]))
        expect(!stability.observe(restarted))
        expect(stability.observe(restarted))

        // 进程信息用于诊断；没有窗口的 Finder 重启没有新增或丢失窗口。
        expect(FinderWindowComparison.compare(
            before: desktop([]),
            after: desktop([], pid: 2, launchTime: 200)
        ) == .unchanged)
        expect(FinderWindowComparison.compare(
            before: .desktop(processes: [], windowIDs: []),
            after: desktop([])
        ) == .unchanged)

        for snapshot in [FinderWindowSnapshot.noGUISession, baseline, restarted] {
            let decoded = try JSONDecoder().decode(
                FinderWindowSnapshot.self,
                from: JSONEncoder().encode(snapshot)
            )
            expect(decoded == snapshot)
        }
        print("Finder window snapshot tests passed: \(passedCount)")
    }

    private static func compare(_ before: [UInt32], _ after: [UInt32]) -> FinderWindowComparison {
        FinderWindowComparison.compare(before: desktop(before), after: desktop(after))
    }

    private static func desktop(
        _ identifiers: [UInt32],
        pid: Int32 = 1,
        launchTime: TimeInterval = 100
    ) -> FinderWindowSnapshot {
        .desktop(
            processes: [FinderWindowProcess(processIdentifier: pid, launchTime: launchTime)],
            windowIDs: Set(identifiers)
        )
    }

    private static func expect(_ condition: Bool, line: UInt = #line) {
        guard condition else {
            FileHandle.standardError.write(Data("Finder window snapshot test failed at line \(line).\n".utf8))
            Darwin.exit(EXIT_FAILURE)
        }
        passedCount += 1
    }
}

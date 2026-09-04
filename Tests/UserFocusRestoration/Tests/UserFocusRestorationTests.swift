import Darwin
import Foundation

@main
private enum UserFocusRestorationTests {
    private static var passedCount = 0

    static func main() {
        exactProcessIsRestored()
        reusedPIDIsRejected()
        missingLaunchTimeIsRejected()
        ordinaryReplacementIsNotActivated()
        uniqueFinderReplacementIsRestored()
        uniqueFinderReplacementWithoutLaunchTimesIsRestored()
        ambiguousFinderReplacementIsRejected()

        print("User focus restoration tests passed: \(passedCount)")
    }

    private static func exactProcessIsRestored() {
        let original = application(pid: 10, launchTime: 100)
        expect(
            UserFocusRestorationResolver.resolve(
                snapshot: original,
                candidates: [original]
            ) == .application(original)
        )
    }

    private static func reusedPIDIsRejected() {
        let original = application(pid: 10, launchTime: 100)
        let reusedPID = application(pid: 10, launchTime: 200)
        expect(
            UserFocusRestorationResolver.resolve(
                snapshot: original,
                candidates: [reusedPID]
            ) == .unavailable
        )
    }

    private static func missingLaunchTimeIsRejected() {
        let original = application(pid: 10, launchTime: nil)
        let indistinguishableReplacement = application(
            pid: 10,
            launchTime: nil
        )
        expect(
            UserFocusRestorationResolver.resolve(
                snapshot: original,
                candidates: [indistinguishableReplacement]
            ) == .unavailable
        )
    }

    private static func ordinaryReplacementIsNotActivated() {
        let original = application(pid: 10, launchTime: 100)
        let replacement = application(pid: 20, launchTime: 200)
        expect(
            UserFocusRestorationResolver.resolve(
                snapshot: original,
                candidates: [replacement]
            ) == .unavailable
        )
    }

    private static func uniqueFinderReplacementIsRestored() {
        let original = application(
            pid: 10,
            launchTime: 100,
            bundleIdentifier: "com.apple.finder",
            executablePath: "/System/Library/CoreServices/Finder.app/Finder"
        )
        let replacement = application(
            pid: 20,
            launchTime: 200,
            bundleIdentifier: "com.apple.finder",
            executablePath: "/System/Library/CoreServices/Finder.app/Finder"
        )
        expect(
            UserFocusRestorationResolver.resolve(
                snapshot: original,
                candidates: [replacement]
            ) == .application(replacement)
        )
    }

    private static func uniqueFinderReplacementWithoutLaunchTimesIsRestored() {
        let original = application(
            pid: 10,
            launchTime: nil,
            bundleIdentifier: "com.apple.finder",
            executablePath: "/System/Library/CoreServices/Finder.app/Finder"
        )
        let replacement = application(
            pid: 20,
            launchTime: nil,
            bundleIdentifier: "com.apple.finder",
            executablePath: "/System/Library/CoreServices/Finder.app/Finder"
        )
        expect(
            UserFocusRestorationResolver.resolve(
                snapshot: original,
                candidates: [replacement]
            ) == .application(replacement)
        )
    }

    private static func ambiguousFinderReplacementIsRejected() {
        let original = application(
            pid: 10,
            launchTime: 100,
            bundleIdentifier: "com.apple.finder",
            executablePath: "/System/Library/CoreServices/Finder.app/Finder"
        )
        let first = application(
            pid: 20,
            launchTime: 200,
            bundleIdentifier: "com.apple.finder",
            executablePath: "/System/Library/CoreServices/Finder.app/Finder"
        )
        let second = application(
            pid: 30,
            launchTime: 300,
            bundleIdentifier: "com.apple.finder",
            executablePath: "/System/Library/CoreServices/Finder.app/Finder"
        )
        expect(
            UserFocusRestorationResolver.resolve(
                snapshot: original,
                candidates: [first, second]
            ) == .unavailable
        )
    }

    private static func application(
        pid: Int32,
        launchTime: TimeInterval?,
        bundleIdentifier: String = "com.microsoft.VSCode",
        executablePath: String = "/Applications/Visual Studio Code.app/Code"
    ) -> UserFocusApplicationIdentity {
        UserFocusApplicationIdentity(
            processIdentifier: pid,
            launchTime: launchTime,
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool
    ) {
        guard condition() else {
            FileHandle.standardError.write(
                Data("User focus restoration test failed.\n".utf8)
            )
            Darwin.exit(EXIT_FAILURE)
        }
        passedCount += 1
    }
}

import AppKit
import ApplicationServices

enum FinderWindowInventory {
    static func currentCount() throws -> Int {
        let finders = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        )
        guard finders.count == 1, let finder = finders.first else {
            throw AutomationFailure.finderUnavailable
        }
        let application = AXUIElementCreateApplication(finder.processIdentifier)
        let windows = try AXClient.elements(
            kAXWindowsAttribute as CFString,
            of: application
        )
        return try windows.filter { window in
            let role = try AXClient.string(
                kAXRoleAttribute as CFString,
                of: window
            )
            let identifier = try AXClient.string(
                kAXIdentifierAttribute as CFString,
                of: window
            )
            return role == kAXWindowRole as String
                && identifier == "FinderWindow"
        }.count
    }
}

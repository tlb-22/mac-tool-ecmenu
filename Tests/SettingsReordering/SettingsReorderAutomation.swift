/**
 在独立 ECMenuPreviews 窗口内发送真实鼠标拖动，验证系统 List 的拖拽路径。
 按明确 PID 和窗口内坐标限定目标，支持中途窗口截图与 Esc 取消，不操作产品配置。
 */

import AppKit
import ApplicationServices
import Foundation

@main
struct SettingsReorderAutomation {
    enum Failure: Error { case usage, permission, target, window, focus, screenshot }

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--check"] {
            print("Accessibility: \(AXIsProcessTrusted()); mouse events: \(CGPreflightPostEventAccess())")
            return
        }
        guard args.count == 7 || args.count == 8,
              let pid = Int32(args[0]), let x1 = Double(args[1]), let y1 = Double(args[2]),
              let x2 = Double(args[3]), let y2 = Double(args[4]), let duration = Double(args[5]),
              duration >= 0.5, duration <= 10,
              args.count == 7 || args[7] == "--cancel" else { throw Failure.usage }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw Failure.permission }
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == "com.axiomace.ecmenu.test.preview" else { throw Failure.target }
        let previous = NSWorkspace.shared.frontmostApplication
        defer { if let previous, !previous.isTerminated { previous.activate() } }
        app.activate(options: [.activateAllWindows])
        let deadline = Date().addingTimeInterval(3)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw Failure.focus }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let window = windows.first(where: {
                  $0[kCGWindowOwnerPID as String] as? Int32 == pid && $0[kCGWindowLayer as String] as? Int == 0
              }),
              let bounds = window[kCGWindowBounds as String] as? [String: Double],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { throw Failure.window }
        let start = CGPoint(x: rect.minX + x1, y: rect.minY + y1)
        let finish = CGPoint(x: rect.minX + x2, y: rect.minY + y2)
        guard rect.contains(start), rect.contains(finish) else { throw Failure.window }
        let screenshot = URL(fileURLWithPath: args[6]).standardizedFileURL
        guard screenshot.path.hasPrefix(FileManager.default.currentDirectoryPath + "/.artifacts/scratch/"),
              !FileManager.default.fileExists(atPath: screenshot.path) else { throw Failure.screenshot }
        let source = CGEventSource(stateID: .hidSystemState)!
        source.localEventsSuppressionInterval = 0
        func mouse(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setDoubleValueField(.mouseEventPressure, value: type == .leftMouseUp ? 0 : 1)
            event.post(tap: .cghidEventTap)
        }
        mouse(.mouseMoved, start)
        Thread.sleep(forTimeInterval: 0.1)
        mouse(.leftMouseDown, start)
        Thread.sleep(forTimeInterval: 0.1)
        for frame in 1...60 {
            let fraction = Double(frame) / 60
            mouse(.leftMouseDragged, CGPoint(x: start.x + (finish.x - start.x) * fraction,
                                            y: start.y + (finish.y - start.y) * fraction))
            Thread.sleep(forTimeInterval: duration / 60)
        }
        defer { mouse(.leftMouseUp, finish) }
        Thread.sleep(forTimeInterval: 0.3)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let region = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        capture.arguments = ["-x", "-R", region, screenshot.path]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0 else { throw Failure.screenshot }
        if args.count == 8 {
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)!.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)!.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.1)
        }
        print("Drag delivered to preview \(pid); in-drag screenshot: \(screenshot.path)")
    }
}

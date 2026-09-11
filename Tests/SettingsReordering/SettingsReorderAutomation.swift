/**
 在独立 ECMenuPreviews 窗口内发送真实鼠标拖动或点击，验证系统 List 与名称编辑的事件路径。
 按明确 PID 和窗口内坐标限定目标，记录点击到字段聚焦的耗时并截图，不操作产品配置。
 */

import AppKit
import ApplicationServices
import Foundation

@main
struct SettingsReorderAutomation {
    enum Failure: Error { case usage, permission, target, window, focus, screenshot, textField, alreadyFocused }

    enum Action {
        case click
        case drag(finish: CGPoint, duration: Double, cancel: Bool)
    }

    struct PreviewWindow: Equatable {
        let number: CGWindowID
        let bounds: CGRect
    }

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--check"] {
            print("Accessibility: \(AXIsProcessTrusted()); mouse events: \(CGPreflightPostEventAccess())")
            return
        }
        let pid: Int32
        let localStart: CGPoint
        let screenshot: URL
        let action: Action
        if args.first == "--click" {
            guard args.count == 5,
                  let processID = Int32(args[1]), let x = Double(args[2]), let y = Double(args[3])
            else { throw Failure.usage }
            pid = processID
            localStart = CGPoint(x: x, y: y)
            screenshot = URL(fileURLWithPath: args[4]).standardizedFileURL
            action = .click
        } else {
            guard args.count == 7 || args.count == 8,
                  let processID = Int32(args[0]), let x1 = Double(args[1]), let y1 = Double(args[2]),
                  let x2 = Double(args[3]), let y2 = Double(args[4]), let duration = Double(args[5]),
                  duration >= 0.5, duration <= 10,
                  args.count == 7 || args[7] == "--cancel" else { throw Failure.usage }
            pid = processID
            localStart = CGPoint(x: x1, y: y1)
            screenshot = URL(fileURLWithPath: args[6]).standardizedFileURL
            action = .drag(finish: CGPoint(x: x2, y: y2), duration: duration, cancel: args.count == 8)
        }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw Failure.permission }
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == "com.axiomace.ecmenu.test.preview" else { throw Failure.target }
        let previous = NSWorkspace.shared.frontmostApplication
        defer { if let previous, !previous.isTerminated { previous.activate() } }
        app.activate(options: [.activateAllWindows])
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var candidate: PreviewWindow?
        var unchangedSince = ProcessInfo.processInfo.systemUptime
        var readyWindow: PreviewWindow?
        // 激活期间可能出现屏幕外的过渡坐标；主窗须在显示器内且位置连续稳定 100 ms。
        while ProcessInfo.processInfo.systemUptime < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
               let current = previewWindow(pid: pid) {
                if current != candidate {
                    candidate = current
                    unchangedSince = ProcessInfo.processInfo.systemUptime
                } else if ProcessInfo.processInfo.systemUptime - unchangedSince >= 0.1 {
                    readyWindow = current
                    break
                }
            } else {
                candidate = nil
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw Failure.focus }
        guard let readyWindow else { throw Failure.window }
        let rect = readyWindow.bounds
        print("Preview \(pid) window \(readyWindow.number) ready at \(rect).")
        let start = CGPoint(x: rect.minX + localStart.x, y: rect.minY + localStart.y)
        guard rect.contains(start) else { throw Failure.window }
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
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw Failure.focus }
        guard previewWindow(pid: pid) == readyWindow else { throw Failure.window }
        mouse(.mouseMoved, start)
        Thread.sleep(forTimeInterval: 0.1)
        switch action {
        case .click:
            let application = AXUIElementCreateApplication(pid)
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(application, Float(start.x), Float(start.y), &hit) == .success,
                  let hit, let field = textField(containing: hit, pid: pid) else { throw Failure.textField }
            guard !isFocused(field, in: application, pid: pid) else { throw Failure.alreadyFocused }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw Failure.focus }
            guard previewWindow(pid: pid) == readyWindow else { throw Failure.window }
            let began = ProcessInfo.processInfo.systemUptime
            mouse(.leftMouseDown, start)
            Thread.sleep(forTimeInterval: 0.03)
            mouse(.leftMouseUp, start)
            var focusedAfter: TimeInterval?
            repeat {
                if isFocused(field, in: application, pid: pid) {
                    focusedAfter = ProcessInfo.processInfo.systemUptime - began
                    break
                }
                Thread.sleep(forTimeInterval: 0.01)
            } while ProcessInfo.processInfo.systemUptime - began < 2
            // 留出一帧以上的绘制时间；耗时取首次 AX 聚焦观测，不含截图等待。
            Thread.sleep(forTimeInterval: 0.1)
            try capture(rect: rect, to: screenshot)
            let identifier = attribute(kAXIdentifierAttribute as CFString, of: field) as? String ?? "AXTextField"
            if let focusedAfter {
                print(String(format: "Click delivered to preview %d; field %@ focused after %.3f s (10 ms polling).", pid, identifier, focusedAfter))
            } else {
                print("Click delivered to preview \(pid); field \(identifier) was not focused within 2.000 s.")
            }
            print("Click screenshot: \(screenshot.path)")
        case let .drag(localFinish, duration, cancel):
            let finish = CGPoint(x: rect.minX + localFinish.x, y: rect.minY + localFinish.y)
            guard rect.contains(finish) else { throw Failure.window }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw Failure.focus }
            guard previewWindow(pid: pid) == readyWindow else { throw Failure.window }
            mouse(.leftMouseDown, start)
            defer { mouse(.leftMouseUp, finish) }
            Thread.sleep(forTimeInterval: 0.1)
            for frame in 1...60 {
                let fraction = Double(frame) / 60
                mouse(.leftMouseDragged, CGPoint(x: start.x + (finish.x - start.x) * fraction,
                                                y: start.y + (finish.y - start.y) * fraction))
                Thread.sleep(forTimeInterval: duration / 60)
            }
            Thread.sleep(forTimeInterval: 0.3)
            try capture(rect: rect, to: screenshot)
            if cancel {
                CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)!.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)!.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.1)
            }
            print("Drag delivered to preview \(pid); in-drag screenshot: \(screenshot.path)")
        }
    }

    static func previewWindow(pid: Int32) -> PreviewWindow? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let window = windows.first(where: {
                  $0[kCGWindowOwnerPID as String] as? Int32 == pid
                      && $0[kCGWindowLayer as String] as? Int == 0
                      && $0[kCGWindowName as String] as? String == "ECMenu"
              }),
              let number = window[kCGWindowNumber as String] as? CGWindowID,
              let bounds = window[kCGWindowBounds as String] as? [String: Double],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success,
              displays.prefix(Int(count)).contains(where: { CGDisplayBounds($0).contains(rect) })
        else { return nil }
        return PreviewWindow(number: number, bounds: rect)
    }

    static func capture(rect: CGRect, to screenshot: URL) throws {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let region = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        capture.arguments = ["-x", "-R", region, screenshot.path]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0 else { throw Failure.screenshot }
    }

    static func attribute(_ name: CFString, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(kAXParentAttribute as CFString, of: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func textField(containing element: AXUIElement, pid: Int32) -> AXUIElement? {
        var current: AXUIElement? = element
        while let candidate = current {
            var owner: pid_t = 0
            guard AXUIElementGetPid(candidate, &owner) == .success, owner == pid else { return nil }
            if attribute(kAXRoleAttribute as CFString, of: candidate) as? String == kAXTextFieldRole {
                return candidate
            }
            current = parent(of: candidate)
        }
        return nil
    }

    static func isFocused(_ field: AXUIElement, in application: AXUIElement, pid: Int32) -> Bool {
        guard let value = attribute(kAXFocusedUIElementAttribute as CFString, of: application),
              CFGetTypeID(value) == AXUIElementGetTypeID(),
              let focusedField = textField(containing: value as! AXUIElement, pid: pid) else { return false }
        if CFEqual(field, focusedField) { return true }
        if let identifier = attribute(kAXIdentifierAttribute as CFString, of: field) as? String {
            return attribute(kAXIdentifierAttribute as CFString, of: focusedField) as? String == identifier
        }
        return false
    }
}

import ApplicationServices
import CoreGraphics

enum FinderPointer {
    static func location(of element: AXUIElement) throws -> CGPoint {
        let frame = try AXClient.frame(of: element)
        guard frame.width > 0, frame.height > 0 else {
            throw AutomationFailure.pointerEventUnavailable
        }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    static func click(at location: CGPoint) throws {
        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: location,
            mouseButton: .left
        ), let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            throw AutomationFailure.pointerEventUnavailable
        }
        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
    }

    static func rightClick(at location: CGPoint) throws {
        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: location,
            mouseButton: .right
        ), let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: location,
            mouseButton: .right
        ) else {
            throw AutomationFailure.pointerEventUnavailable
        }
        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
    }

    static func move(to location: CGPoint) throws {
        guard let mouseMove = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            throw AutomationFailure.pointerEventUnavailable
        }
        mouseMove.post(tap: .cghidEventTap)
    }
}

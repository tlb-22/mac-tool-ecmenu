import Carbon.HIToolbox
import CoreGraphics

enum FinderKey {
    case returnKey
    case escape

    var virtualKey: CGKeyCode {
        switch self {
        case .returnKey: CGKeyCode(kVK_Return)
        case .escape: CGKeyCode(kVK_Escape)
        }
    }
}

enum FinderKeyboard {
    static func press(_ key: FinderKey) throws {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: key.virtualKey,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: key.virtualKey,
            keyDown: false
        ) else {
            throw AutomationFailure.keyboardEventUnavailable
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

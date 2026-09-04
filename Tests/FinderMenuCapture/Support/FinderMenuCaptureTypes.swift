@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

enum FinderMenuContext {
    case container(directory: URL, openingItem: URL)
    case items(ItemSelection)

    var directory: URL {
        switch self {
        case let .container(directory, _): directory
        case let .items(selection): selection.directory
        }
    }

    var representedURLs: [URL] {
        switch self {
        case let .container(_, openingItem): [openingItem]
        case let .items(selection): selection.urls
        }
    }

    var selectedURLs: [URL] {
        switch self {
        case .container: []
        case let .items(selection): selection.urls
        }
    }
}

struct ItemSelection {
    let first: URL
    let remaining: [URL]

    var urls: [URL] { [first] + remaining }
    var directory: URL { first.deletingLastPathComponent().standardizedFileURL }

    init(first: URL, remaining: [URL]) throws {
        let directory = first.deletingLastPathComponent().standardizedFileURL
        guard remaining.allSatisfy({
            $0.deletingLastPathComponent().standardizedFileURL == directory
        }) else {
            throw AutomationFailure.itemsMustShareDirectory
        }
        self.first = first
        self.remaining = remaining
    }
}

enum CLICommand {
    case preflight
    case capture(CaptureRequest)

    struct CaptureRequest {
        let context: FinderMenuContext
        let outputURL: URL
    }

    static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let command = arguments.first else { throw AutomationFailure.usage }

        switch command {
        case "preflight":
            guard arguments.count == 1 else { throw AutomationFailure.usage }
            return .preflight
        case "container":
            guard arguments.count == 3 else { throw AutomationFailure.usage }
            let outputURL = try outputURL(arguments[1])
            let directory = try fileURL(arguments[2])
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw AutomationFailure.directoryDoesNotExist(directory.path)
            }
            let openingItems = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard let openingItem = openingItems.first else {
                throw AutomationFailure.containerIsEmpty(directory.path)
            }
            return .capture(CaptureRequest(
                context: .container(
                    directory: directory,
                    openingItem: openingItem
                ),
                outputURL: outputURL
            ))
        case "items":
            guard arguments.count >= 3 else { throw AutomationFailure.usage }
            let outputURL = try outputURL(arguments[1])
            let urls = try arguments.dropFirst(2).map(fileURL)
            for url in urls where !FileManager.default.fileExists(atPath: url.path) {
                throw AutomationFailure.itemDoesNotExist(url.path)
            }
            return .capture(CaptureRequest(
                context: .items(try ItemSelection(
                    first: urls[0],
                    remaining: Array(urls.dropFirst())
                )),
                outputURL: outputURL
            ))
        default:
            throw AutomationFailure.usage
        }
    }

    private static func fileURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw AutomationFailure.pathMustBeAbsolute(path)
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func outputURL(_ path: String) throws -> URL {
        let outputURL = try fileURL(path)
        guard outputURL.pathExtension.lowercased() == "png" else {
            throw AutomationFailure.outputMustBePNG(path)
        }
        var isDirectory = ObjCBool(false)
        let parent = outputURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: parent.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw AutomationFailure.outputDirectoryDoesNotExist(parent.path)
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AutomationFailure.outputAlreadyExists(outputURL.path)
        }
        return outputURL
    }
}

struct PermissionReport {
    let accessibility: Bool
    let screenCapture: Bool

    static func current(requestIfNeeded: Bool = false) -> PermissionReport {
        let accessibility: Bool
        if requestIfNeeded {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
            ] as CFDictionary
            accessibility = AXIsProcessTrustedWithOptions(options)
        } else {
            accessibility = AXIsProcessTrusted()
        }

        let screenCapture = CGPreflightScreenCaptureAccess()
            || (requestIfNeeded && CGRequestScreenCaptureAccess())
        return PermissionReport(
            accessibility: accessibility,
            screenCapture: screenCapture
        )
    }

    var isReady: Bool { accessibility && screenCapture }
}

struct MenuRect: Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ frame: CGRect) {
        x = frame.minX
        y = frame.minY
        width = frame.width
        height = frame.height
    }
}

struct MenuSnapshot: Equatable {
    let processIdentifier: pid_t
    let rect: MenuRect
    /// 包含空标题分隔项，作为截图前后稳定性指纹。
    let titles: [String]
}

enum AXOperation: String {
    case readAttribute
    case writeAttribute
    case readActions
    case performAction
    case hitTest
    case createObserver
    case registerNotification
}

enum AutomationFailure: Error {
    case usage
    case pathMustBeAbsolute(String)
    case directoryDoesNotExist(String)
    case containerIsEmpty(String)
    case itemDoesNotExist(String)
    case itemsMustShareDirectory
    case outputMustBePNG(String)
    case outputDirectoryDoesNotExist(String)
    case outputAlreadyExists(String)
    case permissions(PermissionReport)
    case finderOpenFailed(String)
    case finderUnavailable
    case interactiveSessionUnavailable
    case finderActivationTimeout
    case newFinderWindowUnavailable
    case finderWindowOwnershipAmbiguous
    case finderWindowTimeout
    case finderSelectionTimeout
    case finderSelectAllUnavailable
    case finderSelectAllScopeMismatch
    case keyboardEventUnavailable
    case pointerEventUnavailable
    case showMenuUnavailable
    case menuOpenTimeout
    case menuStabilityTimeout
    case menuCancelUnavailable
    case menuCloseTimeout
    case sheetCancelUnavailable
    case sheetCloseTimeout
    case windowCloseTimeout
    case focusLost(String)
    case menuChanged
    case screenshotFailed(String)
    case accessibility(AXOperation, AXError)
    case invalidAccessibilityValue(String)
    case unexpected(String)

    var code: String {
        switch self {
        case .usage: "usage"
        case .pathMustBeAbsolute: "path-not-absolute"
        case .directoryDoesNotExist: "directory-not-found"
        case .containerIsEmpty: "container-empty"
        case .itemDoesNotExist: "item-not-found"
        case .itemsMustShareDirectory: "items-not-in-one-directory"
        case .outputMustBePNG: "output-not-png"
        case .outputDirectoryDoesNotExist: "output-directory-not-found"
        case .outputAlreadyExists: "output-exists"
        case .permissions: "permission-denied"
        case .finderOpenFailed: "finder-open-failed"
        case .finderUnavailable: "finder-unavailable"
        case .interactiveSessionUnavailable: "interactive-session-unavailable"
        case .finderActivationTimeout: "finder-activation-timeout"
        case .newFinderWindowUnavailable: "new-finder-window-unavailable"
        case .finderWindowOwnershipAmbiguous: "finder-window-ownership-ambiguous"
        case .finderWindowTimeout: "finder-window-timeout"
        case .finderSelectionTimeout: "finder-selection-timeout"
        case .finderSelectAllUnavailable: "finder-select-all-unavailable"
        case .finderSelectAllScopeMismatch: "finder-select-all-scope-mismatch"
        case .keyboardEventUnavailable: "keyboard-event-unavailable"
        case .pointerEventUnavailable: "pointer-event-unavailable"
        case .showMenuUnavailable: "show-menu-unavailable"
        case .menuOpenTimeout: "menu-open-timeout"
        case .menuStabilityTimeout: "menu-stability-timeout"
        case .menuCancelUnavailable: "menu-cancel-unavailable"
        case .menuCloseTimeout: "menu-close-timeout"
        case .sheetCancelUnavailable: "sheet-cancel-unavailable"
        case .sheetCloseTimeout: "sheet-close-timeout"
        case .windowCloseTimeout: "window-close-timeout"
        case .focusLost: "focus-lost"
        case .menuChanged: "menu-changed"
        case .screenshotFailed: "screenshot-failed"
        case .accessibility: "accessibility-error"
        case .invalidAccessibilityValue: "invalid-accessibility-value"
        case .unexpected: "unexpected-error"
        }
    }

    var message: String {
        switch self {
        case .usage:
            "Usage: FinderMenuAutomation preflight | container <output.png> <directory> | items <output.png> <item> [item ...]"
        case let .pathMustBeAbsolute(path): "Path must be absolute: \(path)"
        case let .directoryDoesNotExist(path): "Directory does not exist: \(path)"
        case let .containerIsEmpty(path):
            "Container capture requires one opening item: \(path)"
        case let .itemDoesNotExist(path): "Item does not exist: \(path)"
        case .itemsMustShareDirectory: "Selected items must share one parent directory."
        case let .outputMustBePNG(path): "Screenshot output must be a PNG path: \(path)"
        case let .outputDirectoryDoesNotExist(path):
            "Screenshot output directory does not exist: \(path)"
        case let .outputAlreadyExists(path): "Screenshot output already exists: \(path)"
        case let .permissions(report):
            "Permissions unavailable (accessibility=\(report.accessibility), screenCapture=\(report.screenCapture))."
        case let .finderOpenFailed(path): "Finder did not open: \(path)"
        case .finderUnavailable: "Finder did not become available."
        case .interactiveSessionUnavailable:
            "Unlock the macOS desktop before capturing Finder menus."
        case .finderActivationTimeout: "Finder did not become frontmost."
        case .newFinderWindowUnavailable:
            "Finder did not expose its Command-N new-window action."
        case .finderWindowOwnershipAmbiguous:
            "Finder created more than one possible window; none was claimed."
        case .finderWindowTimeout: "Finder did not create a focused window."
        case .finderSelectionTimeout: "Finder did not apply the requested selection."
        case .finderSelectAllUnavailable:
            "Finder did not expose its Command-A select-all action."
        case .finderSelectAllScopeMismatch:
            "Select-all capture requires every Finder item to belong to the scenario."
        case .keyboardEventUnavailable:
            "The Finder automation helper could not create a keyboard event."
        case .pointerEventUnavailable:
            "The Finder automation helper could not create a pointer event."
        case .showMenuUnavailable: "Finder did not expose AXShowMenu for this context."
        case .menuOpenTimeout: "The Finder menu did not open."
        case .menuStabilityTimeout: "The Finder menu did not stabilize."
        case .menuCancelUnavailable: "The Finder menu did not expose AXCancel."
        case .menuCloseTimeout: "The Finder menu did not close."
        case .sheetCancelUnavailable:
            "The owned Finder sheet did not expose a cancel action."
        case .sheetCloseTimeout: "The owned Finder sheet did not close."
        case .windowCloseTimeout: "The owned Finder window did not close."
        case let .focusLost(reason): reason
        case .menuChanged: "The Finder menu rect or titles changed during capture."
        case let .screenshotFailed(message): "Screenshot failed: \(message)"
        case let .accessibility(operation, error):
            "\(operation.rawValue) failed with AXError \(error.rawValue)."
        case let .invalidAccessibilityValue(attribute):
            "Finder returned an invalid \(attribute) value."
        case let .unexpected(message): message
        }
    }
}

enum AutomationTiming {
    static let finder: TimeInterval = 10
    static let target: TimeInterval = 10
    static let menu: TimeInterval = 5
    static let stability: TimeInterval = 2
    static let cleanup: TimeInterval = 2
    static let accessibilityRetry: TimeInterval = 0.25
    static let accessibilityRetryAttempts = 3
    static let poll: TimeInterval = 0.05
}

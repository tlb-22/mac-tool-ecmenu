import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum MenuScreenshot {
    static func capture(_ menu: MenuSnapshot, to outputURL: URL) async throws {
        let window = try await menuWindow(matching: menu)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.ignoreShadows = true
        configuration.includeChildWindows = false
        configuration.dynamicRange = .sdr

        let image: CGImage
        do {
            let output = try await SCScreenshotManager.captureScreenshot(
                contentFilter: filter,
                configuration: configuration
            )
            guard let capturedImage = output.sdrImage else {
                throw AutomationFailure.screenshotFailed(
                    "ScreenCaptureKit returned no SDR image."
                )
            }
            image = capturedImage
        } catch let failure as AutomationFailure {
            throw failure
        } catch {
            throw AutomationFailure.screenshotFailed(error.localizedDescription)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw AutomationFailure.screenshotFailed(
                "Could not create the PNG destination."
            )
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AutomationFailure.screenshotFailed("Could not write the PNG file.")
        }
    }

    private static func menuWindow(matching menu: MenuSnapshot) async throws -> SCWindow {
        let deadline = Date().addingTimeInterval(AutomationTiming.stability)
        while true {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.current
            } catch {
                throw AutomationFailure.screenshotFailed(error.localizedDescription)
            }
            let finderWindows = content.windows.filter {
                $0.owningApplication?.processID == menu.processIdentifier
            }
            let matches = finderWindows.filter {
                $0.isOnScreen && framesMatch($0.frame, menu.rect)
            }
            if matches.count == 1 { return matches[0] }
            guard matches.isEmpty, Date() < deadline else {
                let candidates = finderWindows.map {
                    "id=\($0.windowID), onScreen=\($0.isOnScreen), frame=\($0.frame)"
                }.joined(separator: "; ")
                throw AutomationFailure.screenshotFailed(
                    "Expected one Finder menu window, found \(matches.count). "
                        + "AX menu frame=(\(menu.rect.x), \(menu.rect.y), "
                        + "\(menu.rect.width), \(menu.rect.height)); "
                        + "Finder window candidates: \(candidates)"
                )
            }
            // AX 菜单已打开后，窗口服务器可能尚未公布对应的可捕获窗口。
            try await Task.sleep(for: .seconds(AutomationTiming.poll))
        }
    }

    private static func framesMatch(_ frame: CGRect, _ rect: MenuRect) -> Bool {
        let tolerance: CGFloat = 1
        return abs(frame.minX - rect.x) <= tolerance
            && abs(frame.minY - rect.y) <= tolerance
            && abs(frame.width - rect.width) <= tolerance
            && abs(frame.height - rect.height) <= tolerance
    }
}

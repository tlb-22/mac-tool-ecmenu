/**
 将已验证的菜单快照匹配到 ScreenCaptureKit 窗口并保存透明 PNG。
 单菜单定向捕获；父子菜单按屏幕原位一起捕获，排除桌面与其他窗口。
 */

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

        try write(image, to: outputURL)
    }

    static func capture(
        root: MenuSnapshot,
        submenu: MenuSnapshot,
        to outputURL: URL
    ) async throws {
        let rootWindow = try await menuWindow(matching: root)
        let submenuWindow = try await menuWindow(matching: submenu)
        let frame = rootWindow.frame.union(submenuWindow.frame).integral
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.frame.contains(frame) }) else {
            throw AutomationFailure.screenshotFailed(
                "The parent menu and submenu must fit on one display."
            )
        }
        let filter = SCContentFilter(
            display: display,
            including: [rootWindow, submenuWindow]
        )
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = frame.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY
        )
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(frame.width * scale)
        configuration.height = Int(frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsDisplay = true
        configuration.includeChildWindows = false
        // backgroundColor 是 assign 属性，调用方持有颜色直到异步截图结束。
        let backgroundColor = CGColor(gray: 0, alpha: 0)
        configuration.backgroundColor = backgroundColor
        defer { withExtendedLifetime(backgroundColor) {} }
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw AutomationFailure.screenshotFailed(error.localizedDescription)
        }
        try write(image, to: outputURL)
    }

    private static func write(_ image: CGImage, to outputURL: URL) throws {
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

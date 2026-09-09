/**
 验证通过真实 Finder 模板菜单创建文件的完整结果，拥有模板参数与输出文件的验收条件。
 复用通用菜单会话完成截图和点击，等到文件生成及 Finder 选择后才允许调用者清理窗口。
 */

import Foundation

struct NewFileMenuAcceptance {
    let input: FinderMenuCaptureInput
    let parentTitle: String
    let templateTitle: String
    let expectedFileURL: URL

    static func parse(_ arguments: [String]) throws -> Self {
        guard arguments.count == 6,
              !arguments[3].isEmpty, !arguments[4].isEmpty, !arguments[5].isEmpty,
              !arguments[5].contains("/"), arguments[5] != ".", arguments[5] != ".." else {
            throw AutomationFailure.usage
        }
        let input = try FinderMenuCaptureInput.container(
            outputPath: arguments[1], directoryPath: arguments[2]
        )
        let expectedFileURL = input.context.directory.appendingPathComponent(arguments[5])
        guard !FileManager.default.fileExists(atPath: expectedFileURL.path) else {
            throw Failure.alreadyExists(expectedFileURL.path)
        }
        return Self(
            input: input, parentTitle: arguments[3], templateTitle: arguments[4],
            expectedFileURL: expectedFileURL
        )
    }

    @MainActor
    func run(in session: FinderMenuSession) async throws -> MenuSnapshot {
        let submenu = try session.prepareSubmenu(parentTitle: parentTitle)
        try await MenuScreenshot.capture(submenu.snapshot, to: input.outputURL)
        try session.pressItem(named: templateTitle, in: submenu)
        try waitForCreatedFileSelection(in: session)
        return submenu.snapshot
    }

    @MainActor
    private func waitForCreatedFileSelection(in session: FinderMenuSession) throws {
        let deadline = Date().addingTimeInterval(AutomationTiming.target)
        var fileWasCreated = false
        repeat {
            var isDirectory: ObjCBool = false
            fileWasCreated = FileManager.default.fileExists(
                atPath: expectedFileURL.path, isDirectory: &isDirectory
            ) && !isDirectory.boolValue
            if fileWasCreated {
                do {
                    if try session.isSoleSelectedItem(expectedFileURL) { return }
                } catch AutomationFailure.accessibility(.readAttribute, .failure),
                        AutomationFailure.accessibility(.readAttribute, .invalidUIElement),
                        AutomationFailure.accessibility(.readAttribute, .cannotComplete) {
                    // 仅在结果选择的有界等待内重读更新中的 AX 树。
                }
            }
            runLoopSlice(AutomationTiming.poll)
        } while Date() < deadline
        if fileWasCreated { throw AutomationFailure.finderSelectionTimeout }
        throw Failure.creationTimedOut(expectedFileURL.path)
    }

    enum Failure: Error {
        case alreadyExists(String)
        case creationTimedOut(String)

        var code: String {
            switch self {
            case .alreadyExists: "created-file-already-exists"
            case .creationTimedOut: "created-file-timeout"
            }
        }

        var message: String {
            switch self {
            case let .alreadyExists(path): "The expected created file already exists: \(path)"
            case let .creationTimedOut(path): "The template command did not create the expected ordinary file: \(path)"
            }
        }
    }
}

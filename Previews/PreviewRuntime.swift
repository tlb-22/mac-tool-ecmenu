import AppKit
import Foundation

// MARK: - ==================== 预览声明 ====================

/// 一个可以由独立 Preview target 呈现的生产界面场景。
@MainActor
protocol ApplicationPreview {
    /// 命令行和预览脚本共同使用的稳定短标识。
    static var id: String { get }

    /// 呈现真实生产界面，并返回需要在预览期间保活的会话。
    static func present() -> AnyObject
}

/// 抹除具体预览类型，供唯一 Composition 声明和查找。
@MainActor
struct ApplicationPreviewDefinition {
    /// 命令行和预览脚本共同使用的稳定短标识。
    let id: String

    /// 构造并呈现预览会话的唯一入口。
    let present: () -> AnyObject

    /// 保留一个具体预览的身份和呈现行为。
    init<Preview: ApplicationPreview>(_ preview: Preview.Type) {
        precondition(!Preview.id.isEmpty)

        id = Preview.id
        present = Preview.present
    }
}

// MARK: - ==================== 独立进程启动边界 ====================

/// 解析独立 Preview target 的启动参数，并保活当前预览会话。
@MainActor
enum PreviewRuntime {
    /// `preview-ui.sh` 选择一个预览场景时使用的启动参数。
    nonisolated static let launchOption = "--preview-ui"

    /// `preview-ui.sh --list` 查询声明式注册结果时使用的参数。
    nonisolated static let listOption = "--list"

    /// 当前预览的对象图；释放它会同时结束对应界面的模拟状态。
    private static var activeSession: AnyObject?

    /// 当前进程是否只需输出可用预览标识。
    static var shouldListAvailablePreviews: Bool {
        ProcessInfo.processInfo.arguments.contains(listOption)
    }

    /// 从一组完整进程参数中提取预览标识。
    /// - Parameter arguments: 包含可执行文件路径的完整参数序列。
    /// - Returns: `--preview-ui` 后的非空标识；参数缺失或无效时为 `nil`。
    nonisolated static func requestedPreviewID(
        in arguments: [String]
    ) -> String? {
        guard
            let optionIndex = arguments.firstIndex(of: launchOption),
            arguments.indices.contains(optionIndex + 1)
        else {
            return nil
        }

        let previewID = arguments[optionIndex + 1]
        guard !previewID.isEmpty, !previewID.hasPrefix("--") else {
            return nil
        }
        return previewID
    }

    /// 打印唯一注册表中的全部稳定标识，供脚本展示而不复制列表。
    static func printAvailablePreviewIDs() {
        let previewIDs = validatedDefinitions().map(\.id)
        guard
            let output = (previewIDs.joined(separator: "\n") + "\n")
                .data(using: .utf8)
        else {
            return
        }
        FileHandle.standardOutput.write(output)
    }

    /// 呈现命令行选择的预览；无效输入只显示开发提示窗口。
    static func presentRequestedPreview() {
        let definitions = validatedDefinitions()
        let previewIDs = definitions.map(\.id)

        guard
            let requestedID = requestedPreviewID(
                in: ProcessInfo.processInfo.arguments
            ),
            let definition = definitions.first(where: {
                $0.id == requestedID
            })
        else {
            presentInvalidPreviewAlert(availableIDs: previewIDs)
            return
        }

        activeSession = definition.present()
    }

    /// 验证唯一注册表没有重复标识，再交给启动和列表流程共用。
    private static func validatedDefinitions() -> [
        ApplicationPreviewDefinition
    ] {
        let definitions = PreviewComposition.previews
        let previewIDs = definitions.map(\.id)
        precondition(
            Set(previewIDs).count == previewIDs.count,
            "An application preview was registered more than once"
        )
        return definitions
    }

    /// 用可关闭的开发提示说明无效标识，不回退到任何产品窗口。
    private static func presentInvalidPreviewAlert(availableIDs: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法打开界面预览"
        alert.informativeText = availableIDs.isEmpty
            ? "当前没有注册任何界面预览。"
            : "可用标识：\(availableIDs.joined(separator: ", "))"
        alert.addButton(withTitle: "好")

        let controller = NSWindowController(window: alert.window)
        activeSession = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
    }
}

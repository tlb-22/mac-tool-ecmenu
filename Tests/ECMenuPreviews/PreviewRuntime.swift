import AppKit
import Darwin
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

    /// 等待当前预览窗口真正获得焦点，并向截图脚本回报就绪。
    private static var readinessCoordinator:
        PreviewReadinessCoordinator?

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

        let readinessCoordinator = PreviewReadinessCoordinator()
        self.readinessCoordinator = readinessCoordinator
        readinessCoordinator.start()
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

// MARK: - ==================== 截图就绪边界 ====================

/// 只在唯一目标窗口已激活、已布局且稳定后输出机器可读协议。
@MainActor
private final class PreviewReadinessCoordinator: NSObject {
    /// 异常预览不应让调用方无限等待。
    private static let timeout: TimeInterval = 10

    /// 用单调系统时间计算超时，不受时钟调整影响。
    private let deadline = ProcessInfo.processInfo.systemUptime + timeout

    /// 连续两个主循环观测到相同窗口和尺寸，才认为布局稳定。
    private var candidate: Candidate?

    /// 防止就绪后已排队的主循环回调再次输出。
    private var didFinish = false

    /// 截图脚本只能结束一次当前就绪协议。
    private var didAcknowledgeCapture = false

    /// `READY` 后保留的唯一目标窗口。
    private var readyWindow: NSWindow?

    /// 保留 `READY` 已公布的窗口编号，窗口关闭后仍能回执同一身份。
    private var readyWindowNumber: Int?

    /// 记住 `READY` 到截图完成之间是否曾经失去焦点。
    private var didLoseFocus = false

    /// 将截图脚本的 `SIGUSR1` 转换为主队列事件。
    private let captureSignalSource: DispatchSourceSignal

    /// 保留最后一次观测，超时时向调用方说明具体阶段。
    private var lastObservation =
        "no visible top-level preview window"

    /// 将窗口身份与完成布局后的尺寸绑定为一个候选事实。
    private struct Candidate: Equatable {
        let windowNumber: Int
        let frame: NSRect
    }

    /// 提前忽略信号默认终止动作，并由主队列处理截图回执。
    override init() {
        captureSignalSource = DispatchSource.makeSignalSource(
            signal: SIGUSR1,
            queue: .main
        )
        super.init()

        Darwin.signal(SIGUSR1, SIG_IGN)
        captureSignalSource.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.acknowledgeCapture()
            }
        }
        captureSignalSource.resume()
    }

    /// 请求应用激活，然后进入不阻塞 AppKit 的主循环检查。
    func start() {
        NSApp.activate(ignoringOtherApps: true)
        scheduleEvaluation()
    }

    /// 每次只排队到下一个 RunLoop turn，不以固定延时猜测窗口状态。
    private func scheduleEvaluation() {
        RunLoop.main.perform {
            self.evaluate()
        }
    }

    /// 确保唯一顶层窗口获得焦点，并跨主循环验证其布局稳定。
    private func evaluate() {
        guard !didFinish else {
            return
        }
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            fail("preview readiness timed out: \(lastObservation)")
        }

        let windows = NSApp.windows.filter { window in
            window.isVisible
                && !window.isMiniaturized
                && window.parent == nil
                && window.styleMask.contains(.titled)
        }

        guard windows.count <= 1 else {
            let windowNumbers = windows.map(\.windowNumber).sorted()
            fail(
                "expected one visible top-level preview window; found "
                    + "\(windows.count): \(windowNumbers)"
            )
        }
        guard let window = windows.first else {
            candidate = nil
            lastObservation = "no visible top-level preview window"
            scheduleEvaluation()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard NSApp.isActive, window.isKeyWindow else {
            candidate = nil
            lastObservation =
                "window \(window.windowNumber) has not become key"
            scheduleEvaluation()
            return
        }

        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        window.displayIfNeeded()

        let currentCandidate = Candidate(
            windowNumber: window.windowNumber,
            frame: window.frame
        )
        guard candidate == currentCandidate else {
            candidate = currentCandidate
            lastObservation =
                "window \(window.windowNumber) layout has not remained stable "
                + "across a main-loop turn"
            scheduleEvaluation()
            return
        }

        guard NSApp.isActive, window.isKeyWindow else {
            candidate = nil
            lastObservation =
                "window \(window.windowNumber) lost key status"
            scheduleEvaluation()
            return
        }

        beginFocusMonitoring(for: window)
        guard NSApp.isActive, window.isKeyWindow, !didLoseFocus else {
            endFocusMonitoring()
            candidate = nil
            lastObservation =
                "window \(window.windowNumber) lost focus while preparing READY"
            scheduleEvaluation()
            return
        }

        didFinish = true
        writeStandardOutput("READY \(window.windowNumber)")
    }

    /// 从 `READY` 之前开始监听应用和目标窗口的失焦事件。
    private func beginFocusMonitoring(for window: NSWindow) {
        readyWindow = window
        readyWindowNumber = window.windowNumber
        didLoseFocus = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusWasLost(_:)),
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusWasLost(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    /// 失焦事实一旦发生就不可撤销，重新获得焦点也不算成功截图。
    @objc
    private func focusWasLost(_ notification: Notification) {
        didLoseFocus = true
    }

    /// 停止当前窗口的失焦监听，为重试或协议结束清理状态。
    private func endFocusMonitoring() {
        NotificationCenter.default.removeObserver(self)
        readyWindow = nil
        readyWindowNumber = nil
        didLoseFocus = false
    }

    /// 收到截图完成信号后，按整段聚焦记录返回机器可读结果。
    private func acknowledgeCapture() {
        guard !didAcknowledgeCapture else {
            return
        }
        guard
            didFinish,
            let readyWindow,
            let readyWindowNumber
        else {
            fail("received SIGUSR1 before READY")
        }

        let keptFocus = !didLoseFocus
            && NSApp.isActive
            && readyWindow.isKeyWindow

        didAcknowledgeCapture = true
        let result = keptFocus ? "CAPTURED" : "FOCUS_LOST"
        writeStandardOutput("\(result) \(readyWindowNumber)")
        endFocusMonitoring()
        captureSignalSource.cancel()
    }

    /// 通过未缓冲的文件描述符写入完整协议行。
    private func writeStandardOutput(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else {
            fail("could not encode preview readiness output")
        }
        do {
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch {
            fail("could not write preview readiness output: \(error)")
        }
    }

    /// 将明确诊断写入标准错误后以失败状态结束预览进程。
    private func fail(_ message: String) -> Never {
        didFinish = true
        if let data = "ERROR \(message)\n".data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
        Darwin.exit(EXIT_FAILURE)
    }
}

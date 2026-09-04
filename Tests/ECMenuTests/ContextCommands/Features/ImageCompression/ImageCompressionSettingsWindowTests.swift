import AppKit
import XCTest
@testable import ECMenu

/// 验证压缩设置窗口与异步请求之间的一次性完成关系。
@MainActor
final class ImageCompressionSettingsWindowTests: XCTestCase {
    /// 确认设置只恢复对应请求一次，并保存完整有效值。
    func testConfirmationResumesOnceAndPersistsSettings() async throws {
        let fixture = try makeSettingsStore()
        defer { fixture.cleanup() }

        let initialSettings = try XCTUnwrap(
            ImageCompressionSettings(maximumWidth: 900, quality: 6)
        )
        fixture.store.save(initialSettings)

        let completed = expectation(description: "确认后请求完成")
        let prompt = startPrompt(
            settingsStore: fixture.store,
            completed: completed,
            presentWindow: true
        )
        defer { prompt.task.cancel() }

        let controller = try await waitForController(prompt.run)
        defer { controller.dismiss() }

        try maximumWidthField(in: controller).stringValue = "2048"
        try compressButton(in: controller).performClick(nil)

        await fulfillment(of: [completed], timeout: 1)

        let expectedSettings = try XCTUnwrap(
            ImageCompressionSettings(maximumWidth: 2_048, quality: 6)
        )
        XCTAssertEqual(prompt.run.result, expectedSettings)
        XCTAssertEqual(fixture.store.load(), expectedSettings)
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)

        prompt.task.cancel()
        controller.dismiss()
        XCTAssertEqual(prompt.run.result, expectedSettings)
        XCTAssertEqual(fixture.store.load(), expectedSettings)
    }

    /// 标题栏关闭应返回取消，不保存设置，也不重复完成请求。
    func testTitleBarCloseResumesOnceWithoutPersistingSettings() async throws {
        let fixture = try makeSettingsStore()
        defer { fixture.cleanup() }

        let initialSettings = try XCTUnwrap(
            ImageCompressionSettings(maximumWidth: 1_200, quality: 4)
        )
        fixture.store.save(initialSettings)

        let completed = expectation(description: "关闭窗口后请求完成")
        let prompt = startPrompt(
            settingsStore: fixture.store,
            completed: completed,
            presentWindow: true
        )
        defer { prompt.task.cancel() }

        let controller = try await waitForController(prompt.run)
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.isVisible)
        window.performClose(nil)
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertNil(prompt.run.result)
        XCTAssertEqual(fixture.store.load(), initialSettings)
        XCTAssertFalse(window.isVisible)

        controller.dismiss()
        XCTAssertNil(prompt.run.result)
        XCTAssertEqual(fixture.store.load(), initialSettings)
    }

    /// 取消调用方 Task 应关闭对应等待并返回取消。
    func testTaskCancellationResumesPromptWithCancellation() async throws {
        let fixture = try makeSettingsStore()
        defer { fixture.cleanup() }

        let initialSettings = try XCTUnwrap(
            ImageCompressionSettings(maximumWidth: 1_000, quality: 7)
        )
        fixture.store.save(initialSettings)

        let completed = expectation(description: "Task 取消后请求完成")
        let prompt = startPrompt(
            settingsStore: fixture.store,
            completed: completed,
            presentWindow: true
        )
        let controller = try await waitForController(prompt.run)
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.isVisible)
        prompt.task.cancel()
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertNil(prompt.run.result)
        XCTAssertEqual(fixture.store.load(), initialSettings)
        XCTAssertFalse(window.isVisible)

        try maximumWidthField(in: controller).stringValue = "2400"
        try compressButton(in: controller).performClick(nil)
        XCTAssertNil(prompt.run.result)
        XCTAssertEqual(fixture.store.load(), initialSettings)
    }

    /// 请求开始前已经取消的 Task 不应创建设置窗口。
    func testAlreadyCancelledTaskDoesNotPresentWindow() async throws {
        let fixture = try makeSettingsStore()
        defer { fixture.cleanup() }

        let initialSettings = try XCTUnwrap(
            ImageCompressionSettings(maximumWidth: 1_400, quality: 5)
        )
        fixture.store.save(initialSettings)

        let completed = expectation(description: "已取消请求直接完成")
        let run = ImageCompressionPromptRun()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            run.result = await ImageCompressionSettingsPrompt.request(
                settingsStore: fixture.store
            ) { controller in
                run.controller = controller
            }
            run.didReturn = true
            completed.fulfill()
        }
        defer { task.cancel() }

        await fulfillment(of: [completed], timeout: 1)

        XCTAssertTrue(run.didReturn)
        XCTAssertNil(run.result)
        XCTAssertNil(run.controller)
        XCTAssertEqual(fixture.store.load(), initialSettings)
    }

    /// 同时存在的窗口必须各自恢复创建它的请求。
    func testConcurrentPromptsResumeIndependently() async throws {
        let firstFixture = try makeSettingsStore()
        let secondFixture = try makeSettingsStore()
        defer {
            firstFixture.cleanup()
            secondFixture.cleanup()
        }

        let firstInitialSettings = try XCTUnwrap(
            ImageCompressionSettings(maximumWidth: 800, quality: 3)
        )
        let secondInitialSettings = try XCTUnwrap(
            ImageCompressionSettings(maximumWidth: 1_600, quality: 9)
        )
        firstFixture.store.save(firstInitialSettings)
        secondFixture.store.save(secondInitialSettings)

        let firstCompleted = expectation(description: "第一个请求完成")
        let firstPrompt = startPrompt(
            settingsStore: firstFixture.store,
            completed: firstCompleted
        )
        defer { firstPrompt.task.cancel() }
        let firstController = try await waitForController(firstPrompt.run)
        defer { firstController.dismiss() }

        let secondCompleted = expectation(description: "第二个请求完成")
        let secondPrompt = startPrompt(
            settingsStore: secondFixture.store,
            completed: secondCompleted
        )
        defer { secondPrompt.task.cancel() }
        let secondController = try await waitForController(secondPrompt.run)
        defer { secondController.dismiss() }

        try maximumWidthField(in: firstController).stringValue = "1111"
        try maximumWidthField(in: secondController).stringValue = "2222"

        try compressButton(in: secondController).performClick(nil)
        await fulfillment(of: [secondCompleted], timeout: 1)
        XCTAssertTrue(secondPrompt.run.didReturn)
        XCTAssertFalse(firstPrompt.run.didReturn)

        try compressButton(in: firstController).performClick(nil)
        await fulfillment(of: [firstCompleted], timeout: 1)

        XCTAssertEqual(
            firstPrompt.run.result,
            ImageCompressionSettings(maximumWidth: 1_111, quality: 3)
        )
        XCTAssertEqual(
            secondPrompt.run.result,
            ImageCompressionSettings(maximumWidth: 2_222, quality: 9)
        )
        XCTAssertTrue(firstPrompt.run.didReturn)
        XCTAssertTrue(secondPrompt.run.didReturn)
    }

    /// 当前支持语言的完整验证文案必须与按钮同排且不截断。
    func testValidationMessageFitsInEverySupportedLanguage() throws {
        let settings = try XCTUnwrap(
            ImageCompressionSettings(maximumWidth: 1_440, quality: 8)
        )
        let controller = ImageCompressionSettingsWindowController(
            settings: settings,
            completion: { _ in }
        )
        defer { controller.dismiss() }

        try maximumWidthField(in: controller).stringValue = ""
        controller.present()
        let compressButton = try compressButton(in: controller)
        compressButton.performClick(nil)

        let validationLabel = try validationLabel(in: controller)
        let contentView = try XCTUnwrap(controller.window?.contentView)
        XCTAssertFalse(validationLabel.isHidden)

        let applicationBundle = Bundle(for: AppDelegate.self)
        for language in ["en", "zh-Hans"] {
            let localizationPath = try XCTUnwrap(
                applicationBundle.path(
                    forResource: language,
                    ofType: "lproj"
                ),
                language
            )
            let localizationBundle = try XCTUnwrap(
                Bundle(path: localizationPath),
                language
            )
            validationLabel.stringValue = localizationBundle.localizedString(
                forKey: "imageCompression.validation.targetWidth",
                value: nil,
                table: "Localizable"
            )
            contentView.layoutSubtreeIfNeeded()

            let validationFrame = validationLabel.convert(
                validationLabel.bounds,
                to: contentView
            )
            let buttonFrame = compressButton.convert(
                compressButton.bounds,
                to: contentView
            )

            XCTAssertGreaterThanOrEqual(
                validationLabel.frame.width + 0.5,
                validationLabel.intrinsicContentSize.width,
                "Validation message is truncated in \(language)"
            )
            XCTAssertEqual(
                validationFrame.midY,
                buttonFrame.midY,
                accuracy: 1,
                "Validation message and button are not on one row in \(language)"
            )
        }
    }

    /// 创建隔离的偏好容器，避免窗口测试读写应用设置。
    private func makeSettingsStore() throws -> (
        store: ImageCompressionSettingsStore,
        cleanup: () -> Void
    ) {
        let suiteName =
            "ImageCompressionSettingsWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        return (
            ImageCompressionSettingsStore(defaults: defaults),
            { defaults.removePersistentDomain(forName: suiteName) }
        )
    }

    /// 启动一项真实异步请求，只替换设置存储和窗口呈现副作用。
    private func startPrompt(
        settingsStore: ImageCompressionSettingsStore,
        completed: XCTestExpectation,
        presentWindow: Bool = false
    ) -> (
        run: ImageCompressionPromptRun,
        task: Task<Void, Never>
    ) {
        let run = ImageCompressionPromptRun()
        let task = Task { @MainActor in
            run.result = await ImageCompressionSettingsPrompt.request(
                settingsStore: settingsStore
            ) { controller in
                run.controller = controller
                if presentWindow {
                    controller.present()
                }
            }
            run.didReturn = true
            completed.fulfill()
        }
        return (run, task)
    }

    /// 有限让出主执行器，等待请求创建自己的窗口控制器。
    private func waitForController(
        _ run: ImageCompressionPromptRun
    ) async throws -> ImageCompressionSettingsWindowController {
        for _ in 0..<100 {
            if let controller = run.controller {
                return controller
            }
            await Task.yield()
        }

        return try XCTUnwrap(
            run.controller,
            "压缩设置请求没有创建窗口控制器"
        )
    }

    /// 查找设置窗口中唯一可编辑的目标宽度字段。
    private func maximumWidthField(
        in controller: ImageCompressionSettingsWindowController
    ) throws -> NSTextField {
        try XCTUnwrap(
            descendant(
                of: NSTextField.self,
                in: controller.window?.contentView
            ) { $0.isEditable },
            "没有找到目标宽度字段"
        )
    }

    /// 通过稳定控件身份查找确认按钮，不依赖本地化标题或窗口状态。
    private func compressButton(
        in controller: ImageCompressionSettingsWindowController
    ) throws -> NSButton {
        try XCTUnwrap(
            descendant(
                of: NSButton.self,
                in: controller.window?.contentView
            ) {
                $0.identifier
                    == ImageCompressionSettingsControlIdentifier.confirmButton
            },
            "没有找到确认按钮"
        )
    }

    /// 通过稳定控件身份查找底部验证文案。
    private func validationLabel(
        in controller: ImageCompressionSettingsWindowController
    ) throws -> NSTextField {
        try XCTUnwrap(
            descendant(
                of: NSTextField.self,
                in: controller.window?.contentView
            ) {
                $0.identifier
                    == ImageCompressionSettingsControlIdentifier.validationLabel
            },
            "没有找到验证文案"
        )
    }

    /// 深度优先查找满足条件的指定 AppKit 视图。
    private func descendant<View: NSView>(
        of type: View.Type,
        in root: NSView?,
        matching predicate: (View) -> Bool
    ) -> View? {
        guard let root else {
            return nil
        }
        if let view = root as? View, predicate(view) {
            return view
        }
        for subview in root.subviews {
            if let match = descendant(
                of: type,
                in: subview,
                matching: predicate
            ) {
                return match
            }
        }
        return nil
    }
}

/// 保存一项窗口请求的测试观测结果。
@MainActor
private final class ImageCompressionPromptRun {
    /// 请求创建的真实窗口控制器。
    var controller: ImageCompressionSettingsWindowController?

    /// continuation 返回的设置；取消时为 nil。
    var result: ImageCompressionSettings?

    /// 异步请求是否已经返回。
    var didReturn = false
}

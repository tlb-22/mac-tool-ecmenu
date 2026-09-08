import AppKit
import SwiftUI
import XCTest
@testable import ECMenu

/// 通过真实原生字段的 mouseDown 和共享 field editor 验证页面焦点交接。
@MainActor
final class FileTemplatesPageTests: XCTestCase {
    func testUnchangedNamesSwitchBothDirectionsWithoutReplacingNativeFields() async throws {
        let fixture = try FileTemplatesPageFixture()
        let host = FileTemplatesNativePageHost(harness: fixture.harness)
        defer { host.close() }
        let first = try await field(for: fixture.firstName, in: host)
        let second = try await field(for: fixture.firstFileName, in: host)

        try click(first, in: host)
        try await assertEditing(fixture.firstName, field: first, host: host)
        try click(second, in: host)
        try await assertEditing(fixture.firstFileName, field: second, host: host)
        try click(first, in: host)
        try await assertEditing(fixture.firstName, field: first, host: host)
        XCTAssertTrue(fixture.harness.saved.isEmpty)
        assertIdentity(first, target: fixture.firstName, in: host)
        assertIdentity(second, target: fixture.firstFileName, in: host)
        try typeIntoFirstResponder("Typed into display name", in: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "Typed into display name")
        XCTAssertEqual(second.stringValue, "untitled.txt")
    }

    func testChangedNamesSwitchBothDirectionsAndTypingUsesTheNewFirstResponder() async throws {
        let fixture = try FileTemplatesPageFixture()
        let host = FileTemplatesNativePageHost(harness: fixture.harness)
        defer { host.close() }
        let first = try await field(for: fixture.firstName, in: host)
        let second = try await field(for: fixture.firstFileName, in: host)

        try click(first, in: host)
        try await assertEditing(fixture.firstName, field: first, host: host)
        try typeIntoFirstResponder("Notes", in: host)
        try click(second, in: host)
        try await assertEditing(fixture.firstFileName, field: second, host: host)
        try typeIntoFirstResponder("notes.md", in: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "notes.md")
        try click(first, in: host)
        try await assertEditing(fixture.firstName, field: first, host: host)
        try typeIntoFirstResponder("Latest Notes", in: host)

        XCTAssertEqual(fixture.harness.saved, [
            FileTemplatesNativeSave(target: fixture.firstName, value: "Notes"),
            FileTemplatesNativeSave(target: fixture.firstFileName, value: "notes.md"),
        ])
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "Latest Notes")
        assertIdentity(first, target: fixture.firstName, in: host)
        assertIdentity(second, target: fixture.firstFileName, in: host)
        XCTAssertEqual(second.stringValue, "notes.md")
    }

    func testKeyboardAndSelectTextEntryPreserveTheOriginalValueAndSaveTheFirstInput() async throws {
        let fixture = try FileTemplatesPageFixture()
        let host = FileTemplatesNativePageHost(harness: fixture.harness)
        defer { host.close() }
        let first = try await field(for: fixture.firstName, in: host)
        let second = try await field(for: fixture.firstFileName, in: host)

        _ = host.window.makeFirstResponder(first)
        try await assertEditing(fixture.firstName, field: first, host: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.originalValue, "TXT")
        try typeIntoFirstResponder("K", in: host)
        first.selectText(nil)
        try await assertEditing(fixture.firstName, field: first, host: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "K")
        second.selectText(nil)
        try await assertEditing(fixture.firstFileName, field: second, host: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.originalValue, "untitled.txt")
        try typeIntoFirstResponder("F.txt", in: host)
        let finished = await fixture.harness.nameEditing.finishEditing()
        XCTAssertTrue(finished)
        XCTAssertEqual(fixture.harness.saved, [
            FileTemplatesNativeSave(target: fixture.firstName, value: "K"),
            FileTemplatesNativeSave(target: fixture.firstFileName, value: "F.txt"),
        ])
        assertIdentity(first, target: fixture.firstName, in: host)
        assertIdentity(second, target: fixture.firstFileName, in: host)

        let third = try await field(for: fixture.secondName, in: host)
        host.window.autorecalculatesKeyViewLoop = false
        first.nextKeyView = second
        second.nextKeyView = third
        third.nextKeyView = first
        XCTAssertTrue(first.nextValidKeyView === second)
        _ = host.window.makeFirstResponder(first)
        try await assertEditing(fixture.firstName, field: first, host: host)
        try typeIntoFirstResponder("Tab name", in: host)
        let editor = try XCTUnwrap(host.window.firstResponder as? NSTextView)
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        try await assertEditing(fixture.firstFileName, field: second, host: host)
        try typeIntoFirstResponder("tab.txt", in: host)
        let tabFinished = await fixture.harness.nameEditing.finishEditing()
        XCTAssertTrue(tabFinished)
        XCTAssertEqual(Array(fixture.harness.saved.suffix(2)), [
            FileTemplatesNativeSave(target: fixture.firstName, value: "Tab name"),
            FileTemplatesNativeSave(target: fixture.firstFileName, value: "tab.txt"),
        ])
    }

    func testCrossRowMouseSwitchKeepsTypingInTheChosenTemplate() async throws {
        let fixture = try FileTemplatesPageFixture()
        let host = FileTemplatesNativePageHost(harness: fixture.harness)
        defer { host.close() }
        let first = try await field(for: fixture.firstName, in: host)
        let second = try await field(for: fixture.secondName, in: host)
        try click(first, in: host)
        try await assertEditing(fixture.firstName, field: first, host: host)
        try typeIntoFirstResponder("First changed", in: host)
        try click(second, in: host)
        try await assertEditing(fixture.secondName, field: second, host: host)
        try typeIntoFirstResponder("Second changed", in: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "Second changed")
        XCTAssertEqual(fixture.harness.saved, [FileTemplatesNativeSave(target: fixture.firstName, value: "First changed")])
        XCTAssertEqual(first.stringValue, "First changed")
        assertIdentity(first, target: fixture.firstName, in: host)
        assertIdentity(second, target: fixture.secondName, in: host)
    }

    func testSuspendedSaveKeepsFileButtonsEnabledAndLatestMouseTargetGetsTheEditor() async throws {
        let fixture = try FileTemplatesPageFixture()
        let gate = FileTemplatesNativeSaveGate()
        fixture.harness.saveBoundary = { try await gate.save($0) }
        let host = FileTemplatesNativePageHost(harness: fixture.harness)
        defer {
            gate.finish()
            host.close()
        }
        let first = try await field(for: fixture.firstName, in: host)
        let middle = try await field(for: fixture.firstFileName, in: host)
        let latest = try await field(for: fixture.secondName, in: host)
        try click(first, in: host)
        try await assertEditing(fixture.firstName, field: first, host: host)
        for button in try operationButtons(in: host) { XCTAssertTrue(button.isEnabled) }
        try typeIntoFirstResponder("Saved once", in: host)
        try click(middle, in: host)
        await gate.waitUntilSaving()
        host.layout()
        XCTAssertTrue(fixture.harness.isUpdating)
        XCTAssertTrue(fixture.harness.nameEditing.isTransitioning)
        XCTAssertFalse(accessibilityElements(in: host.view).contains { $0.role == .progressIndicator },
                       "Saving an inline name must not flash the global file-operation progress indicator")
        for button in try operationButtons(in: host) {
            XCTAssertTrue(button.isEnabled, "Name persistence must not disable unrelated file-operation buttons")
        }
        try click(latest, in: host)
        gate.finish()
        try await assertEditing(fixture.secondName, field: latest, host: host)
        try typeIntoFirstResponder("Latest target", in: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "Latest target")
        XCTAssertEqual(gate.values, [FileTemplatesNativeSave(target: fixture.firstName, value: "Saved once")])
        assertIdentity(middle, target: fixture.firstFileName, in: host)
    }

    func testFileOperationSaveFailureKeepsOriginalNativeFocusAndDoesNotRunOperation() async throws {
        let fixture = try FileTemplatesPageFixture()
        let host = FileTemplatesNativePageHost(harness: fixture.harness)
        defer { host.close() }
        let name = try await field(for: fixture.firstName, in: host)
        try click(name, in: host)
        try await assertEditing(fixture.firstName, field: name, host: host)
        try typeIntoFirstResponder("  ", in: host)
        let open = try XCTUnwrap(operationButtons(in: host).first {
            $0.text.contains(String(localized: FileTemplatesText.open))
        })
        XCTAssertTrue(open.press())
        for _ in 0..<100 {
            if fixture.harness.nameEditing.draft?.errorMessage != nil,
               !fixture.harness.nameEditing.isTransitioning { break }
            await Task.yield()
        }
        try await assertEditing(fixture.firstName, field: name, host: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "  ")
        XCTAssertNotNil(fixture.harness.nameEditing.draft?.errorMessage)
        XCTAssertTrue(fixture.harness.openedIDs.isEmpty)
        XCTAssertTrue(fixture.harness.saved.isEmpty)
        XCTAssertTrue(name.isEnabled)
        assertIdentity(name, target: fixture.firstName, in: host)
        try typeIntoFirstResponder("Corrected", in: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "Corrected")
    }

    private func assertIdentity(_ field: FileTemplateNameNativeField, target: FileTemplateNameTarget, in host: FileTemplatesNativePageHost) {
        host.layout()
        XCTAssertTrue(nativeFields(in: host.view).first(where: { $0.editingCoordinator?.target == target }) === field,
                      "A name field must preserve its native view identity across edits")
    }

    private func field(for target: FileTemplateNameTarget, in host: FileTemplatesNativePageHost) async throws -> FileTemplateNameNativeField {
        for _ in 0..<100 {
            host.layout()
            if let field = nativeFields(in: host.view).first(where: { $0.editingCoordinator?.target == target }) {
                return field
            }
            await Task.yield()
        }
        return try XCTUnwrap(nil as FileTemplateNameNativeField?, "The actual page did not create the target native text field")
    }

    private func nativeFields(in view: NSView) -> [FileTemplateNameNativeField] {
        (view as? FileTemplateNameNativeField).map { [$0] } ?? view.subviews.flatMap(nativeFields)
    }

    private func click(_ field: FileTemplateNameNativeField, in host: FileTemplatesNativePageHost) throws {
        let position = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: position, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        field.mouseDown(with: event)
    }

    private func assertEditing(_ target: FileTemplateNameTarget, field: FileTemplateNameNativeField, host: FileTemplatesNativePageHost) async throws {
        for _ in 0..<100 {
            if host.harness.nameEditing.draft?.target == target, !host.harness.nameEditing.isTransitioning { break }
            await Task.yield()
        }
        host.layout()
        XCTAssertEqual(host.harness.nameEditing.draft?.target, target)
        XCTAssertFalse(host.harness.nameEditing.isTransitioning)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView, "Target field must own the native field editor")
        XCTAssertTrue(host.window.firstResponder === editor, "Visible editing state must correspond to the native first responder")
        XCTAssertTrue(editor.isEditable)
    }

    private func typeIntoFirstResponder(_ text: String, in host: FileTemplatesNativePageHost) throws {
        let editor = try XCTUnwrap(host.window.firstResponder as? NSTextView)
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        XCTAssertEqual(editor.string, text)
    }

    private func operationButtons(in host: FileTemplatesNativePageHost) throws -> [FileTemplatesNativeAccessibilityElement] {
        host.layout()
        let buttons = accessibilityElements(in: host.view).filter { $0.role == .button }
        return try [FileTemplatesText.open, FileTemplatesText.replace, FileTemplatesText.delete, FileTemplatesText.add].map { title in
            try XCTUnwrap(buttons.first { $0.text.contains(String(localized: title)) }, "A template file-operation button is missing")
        }
    }

    private func accessibilityElements(in root: NSView) -> [FileTemplatesNativeAccessibilityElement] {
        var visited: Set<ObjectIdentifier> = []
        func visit(_ element: FileTemplatesNativeAccessibilityElement) -> [FileTemplatesNativeAccessibilityElement] {
            guard visited.insert(element.identity).inserted else { return [] }
            return [element] + element.children.flatMap(visit)
        }
        return visit(FileTemplatesNativeAccessibilityElement(object: root))
    }
}

@MainActor
private struct FileTemplatesPageFixture {
    let harness: FileTemplatesNativePageHarness
    let firstName: FileTemplateNameTarget
    let firstFileName: FileTemplateNameTarget
    let secondName: FileTemplateNameTarget

    init() throws {
        let first = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        let second = try FileTemplate(displayName: "MD", defaultFileName: "untitled.md")
        harness = FileTemplatesNativePageHarness(templates: [first, second])
        firstName = .init(templateID: first.id, field: .displayName)
        firstFileName = .init(templateID: first.id, field: .defaultFileName)
        secondName = .init(templateID: second.id, field: .displayName)
    }
}

nonisolated private struct FileTemplatesNativeSave: Equatable {
    let target: FileTemplateNameTarget
    let value: String
}

@MainActor
private final class FileTemplatesNativePageHarness: ObservableObject {
    let nameEditing = FileTemplateNameEditingSession()
    @Published private(set) var templates: [FileTemplate]
    @Published private(set) var isUpdating = false
    private(set) var saved: [FileTemplatesNativeSave] = []
    private(set) var openedIDs: [FileTemplateID] = []
    var saveBoundary: ((FileTemplatesNativeSave) async throws -> Void)?

    init(templates: [FileTemplate]) { self.templates = templates }
    func open(_ id: FileTemplateID) { openedIDs.append(id) }

    func update(_ id: FileTemplateID, field: FileTemplateNameField, value: String) async throws {
        let change = FileTemplatesNativeSave(target: .init(templateID: id, field: field), value: value)
        isUpdating = true
        defer { isUpdating = false }
        try await saveBoundary?(change)
        let position = try XCTUnwrap(templates.firstIndex { $0.id == id })
        templates[position] = try field.updating(templates[position], to: value)
        saved.append(change)
    }
}

@MainActor
private struct FileTemplatesNativePageContent: View {
    @ObservedObject var harness: FileTemplatesNativePageHarness
    var body: some View {
        FileTemplatesPage(
            state: .ready(harness.templates), isUpdating: harness.isUpdating, nameEditing: harness.nameEditing,
            importTemplate: {}, updateName: { try await harness.update($0, field: $1, value: $2) },
            openTemplate: { harness.open($0) }, replaceTemplate: { _ in }, removeTemplate: { _ in }, reload: {}
        )
    }
}

/// 隐藏窗口让字段使用 AppKit 共享编辑器，所有事件只发往测试自己的控件。
@MainActor
private final class FileTemplatesNativePageHost {
    let harness: FileTemplatesNativePageHarness
    let view: NSHostingView<FileTemplatesNativePageContent>
    let window: NSWindow

    init(harness: FileTemplatesNativePageHarness) {
        self.harness = harness
        let frame = NSRect(x: 0, y: 0, width: 720, height: 420)
        view = NSHostingView(rootView: FileTemplatesNativePageContent(harness: harness))
        view.frame = frame
        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = view
        layout()
    }
    func layout() { view.layoutSubtreeIfNeeded() }
    func close() {
        harness.nameEditing.cancelEditing()
        window.contentView = nil
        window.close()
    }
}

@MainActor
private final class FileTemplatesNativeSaveGate {
    private(set) var values: [FileTemplatesNativeSave] = []
    private var entered: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Error>?
    func save(_ value: FileTemplatesNativeSave) async throws {
        values.append(value)
        guard values.count == 1 else {
            XCTFail("A single field handoff saved more than once")
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            entered?.resume()
            entered = nil
        }
    }
    func waitUntilSaving() async {
        if completion != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func finish() {
        completion?.resume()
        completion = nil
    }
}

/// SwiftUI 的实际节点通过公开 Objective-C 可访问性方法读取，无需 AX 授权。
@MainActor
private struct FileTemplatesNativeAccessibilityElement {
    let object: AnyObject
    var identity: ObjectIdentifier { ObjectIdentifier(object) }
    var role: NSAccessibility.Role? { object.accessibilityRole?() }
    var isEnabled: Bool { object.isAccessibilityEnabled?() ?? false }
    func press() -> Bool { object.accessibilityPerformPress?() ?? false }
    var text: [String] {
        let value: Any? = object.accessibilityValue?()
        return [object.accessibilityLabel?(), object.accessibilityTitle?(), value as? String]
            .compactMap { $0 }
    }
    var children: [FileTemplatesNativeAccessibilityElement] {
        let children: [Any] = object.accessibilityChildren?() ?? []
        return children.map { FileTemplatesNativeAccessibilityElement(object: $0 as AnyObject) }
    }
}

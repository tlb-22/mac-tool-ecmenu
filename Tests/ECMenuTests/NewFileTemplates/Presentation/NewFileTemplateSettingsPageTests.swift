/**
 通过真实 AppKit 字段和共享 field editor 验证模板页编辑与文件操作的衔接。
 覆盖跨行焦点、异步保存、页面操作互斥、行稳定性，以及失败后的输入与焦点恢复。
 */

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import ECMenu

/// 通过真实原生字段的 mouseDown 和共享 field editor 验证页面焦点交接。
@MainActor
final class NewFileTemplateSettingsPageTests: XCTestCase {
    func testUnchangedNamesSwitchBothDirectionsWithoutReplacingNativeFields() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
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
        let fixture = try NewFileTemplateSettingsPageFixture()
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
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
            NewFileTemplatesNativeSave(target: fixture.firstName, value: "Notes"),
            NewFileTemplatesNativeSave(target: fixture.firstFileName, value: "notes.md"),
        ])
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "Latest Notes")
        assertIdentity(first, target: fixture.firstName, in: host)
        assertIdentity(second, target: fixture.firstFileName, in: host)
        XCTAssertEqual(second.stringValue, "notes.md")
    }

    func testKeyboardAndSelectTextEntryPreserveTheOriginalValueAndSaveTheFirstInput() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
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
            NewFileTemplatesNativeSave(target: fixture.firstName, value: "K"),
            NewFileTemplatesNativeSave(target: fixture.firstFileName, value: "F.txt"),
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
            NewFileTemplatesNativeSave(target: fixture.firstName, value: "Tab name"),
            NewFileTemplatesNativeSave(target: fixture.firstFileName, value: "tab.txt"),
        ])
    }

    func testCrossRowMouseSwitchKeepsTypingInTheChosenTemplate() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
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
        XCTAssertEqual(fixture.harness.saved, [NewFileTemplatesNativeSave(target: fixture.firstName, value: "First changed")])
        XCTAssertEqual(first.stringValue, "First changed")
        assertIdentity(first, target: fixture.firstName, in: host)
        assertIdentity(second, target: fixture.secondName, in: host)
    }

    func testSuspendedSaveKeepsFileButtonsEnabledAndLatestMouseTargetGetsTheEditor() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let gate = NewFileTemplatesNativeSaveGate()
        fixture.harness.saveBoundary = { try await gate.save($0) }
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
        defer {
            gate.finish()
            host.close()
        }
        let first = try await field(for: fixture.firstName, in: host)
        let middle = try await field(for: fixture.firstFileName, in: host)
        let latest = try await field(for: fixture.secondName, in: host)
        try click(first, in: host)
        try await assertEditing(fixture.firstName, field: first, host: host)
        for button in try await operationButtons(in: host) { XCTAssertTrue(button.isEnabled) }
        try typeIntoFirstResponder("Saved once", in: host)
        try click(middle, in: host)
        await gate.waitUntilSaving()
        host.layout()
        XCTAssertTrue(fixture.harness.isUpdating)
        XCTAssertTrue(fixture.harness.nameEditing.isTransitioning)
        XCTAssertFalse(accessibilityElements(in: host.view).contains { $0.role == .progressIndicator },
                       "Saving an inline name must not flash the global file-operation progress indicator")
        for button in try await operationButtons(in: host) {
            XCTAssertTrue(button.isEnabled, "Name persistence must not disable unrelated file-operation buttons")
        }
        try click(latest, in: host)
        gate.finish()
        try await assertEditing(fixture.secondName, field: latest, host: host)
        try typeIntoFirstResponder("Latest target", in: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "Latest target")
        XCTAssertEqual(gate.values, [NewFileTemplatesNativeSave(target: fixture.firstName, value: "Saved once")])
        assertIdentity(middle, target: fixture.firstFileName, in: host)
    }

    func testDeletionKeepsThePageAppearanceAndRejectsConcurrentActionsUntilOnlyTheTargetRowIsRemoved() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let gate = NewFileTemplatesNativeRemovalGate()
        fixture.harness.removalBoundary = { try await gate.remove($0) }
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
        defer {
            gate.finish()
            host.close()
        }
        _ = try await field(for: fixture.firstName, in: host)
        let retainedField = try await field(for: fixture.secondName, in: host)
        let originalTemplates = fixture.harness.templates
        let originalFields = nativeFields(in: host.view)
        let originalColors = originalFields.map(\.textColor)
        let deletionButtons = try await operationButtons(in: host)
        let deletion = try XCTUnwrap(deletionButtons.first {
            $0.text.contains(String(localized: NewFileTemplatesText.delete))
        })
        XCTAssertTrue(deletion.press())
        await gate.waitUntilRemoving()

        // 不先刷新 NSView：入口必须立即读到删除锁，而不能依赖之后的 SwiftUI 更新。
        let coordinator = try XCTUnwrap(retainedField.editingCoordinator)
        coordinator.requestEditing()
        XCTAssertFalse(fixture.harness.nameEditing.isTransitioning)
        retainedField.selectText(nil)
        XCTAssertFalse(fixture.harness.nameEditing.isTransitioning)
        XCTAssertFalse(retainedField.becomeFirstResponder())
        let point = retainedField.convert(NSPoint(x: retainedField.bounds.midX, y: retainedField.bounds.midY), to: host.view)
        let hit = try hitView(at: point, in: host)
        XCTAssertTrue(hit === retainedField)
        try mouseDown(on: hit, at: point, in: host)
        XCTAssertFalse(fixture.harness.nameEditing.isTransitioning)
        XCTAssertNil(fixture.harness.nameEditing.draft)
        XCTAssertNil(retainedField.currentEditor())

        host.layout()
        XCTAssertTrue(fixture.harness.isUpdating)
        XCTAssertEqual(fixture.harness.templates, originalTemplates)
        XCTAssertEqual(nativeFields(in: host.view).map(ObjectIdentifier.init), originalFields.map(ObjectIdentifier.init))
        XCTAssertEqual(originalFields.map(\.textColor), originalColors)
        XCTAssertTrue(originalFields.allSatisfy(\.isEnabled))
        let actions = accessibilityElements(in: host.view).filter { $0.role == .button }
        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.allSatisfy(\.isEnabled), "Removing one row must not dim every action button")
        XCTAssertFalse(accessibilityElements(in: host.view).contains { $0.role == .progressIndicator })

        // 删除按钮保留正常外观，重复删除和其它入口仍由操作重入规则拒绝。
        for action in actions { XCTAssertTrue(action.press()) }
        await Task.yield()
        XCTAssertEqual(gate.ids, [fixture.firstName.templateID])
        XCTAssertEqual(fixture.harness.removalAttempts, [fixture.firstName.templateID])
        XCTAssertTrue(fixture.harness.openedIDs.isEmpty)
        XCTAssertTrue(fixture.harness.replacedIDs.isEmpty)
        XCTAssertEqual(fixture.harness.importCount, 0)
        XCTAssertTrue(fixture.harness.saved.isEmpty)

        // 页面身份变化不应重置由状态页持有的文件操作锁。
        host.rebuildPage()
        let rebuiltRemovedField = try await field(for: fixture.firstName, in: host)
        let rebuiltRetainedField = try await field(for: fixture.secondName, in: host)
        let rebuiltDeletionButtons = try await operationButtons(in: host)
        let rebuiltDeletion = try XCTUnwrap(rebuiltDeletionButtons.first {
            $0.text.contains(String(localized: NewFileTemplatesText.delete))
        })
        XCTAssertTrue(rebuiltDeletion.press())
        try XCTUnwrap(rebuiltRetainedField.editingCoordinator).requestEditing()
        XCTAssertFalse(fixture.harness.nameEditing.isTransitioning)
        XCTAssertNil(fixture.harness.nameEditing.draft)
        await Task.yield()
        XCTAssertEqual(gate.ids, [fixture.firstName.templateID])
        XCTAssertEqual(fixture.harness.removalAttempts, [fixture.firstName.templateID])

        gate.finish()
        for _ in 0..<100 {
            if fixture.harness.templates.count == originalTemplates.count - 1,
               !fixture.harness.isUpdating,
               fixture.harness.actions.allowsNameEditing(fixture.secondName, in: fixture.harness.nameEditing) { break }
            await Task.yield()
        }
        // 不等待下一次 NSView 更新；操作结束后的第一次选择立即进入编辑。
        rebuiltRetainedField.selectText(nil)
        try await assertEditing(fixture.secondName, field: rebuiltRetainedField, host: host)
        host.layout()
        XCTAssertEqual(fixture.harness.templates, originalTemplates.filter { $0.id != fixture.firstName.templateID })
        XCTAssertEqual(fixture.harness.removedIDs, [fixture.firstName.templateID])
        XCTAssertFalse(nativeFields(in: host.view).contains { $0 === rebuiltRemovedField })
        assertIdentity(rebuiltRetainedField, target: fixture.secondName, in: host)
    }

    func testDeletionRejectsNewEditingInsideTheSynchronousEndNotification() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let gate = NewFileTemplatesNativeRemovalGate()
        fixture.harness.removalBoundary = { try await gate.remove($0) }
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
        defer {
            gate.finish()
            host.close()
        }
        let source = try await field(for: fixture.firstName, in: host)
        let other = try await field(for: fixture.secondName, in: host)
        let otherCoordinator = try XCTUnwrap(other.editingCoordinator)
        try click(source, in: host)
        try await assertEditing(fixture.firstName, field: source, host: host)
        try typeIntoFirstResponder("Save then delete", in: host)

        var endNotificationCount = 0
        let observer = NotificationCenter.default.publisher(
            for: NSControl.textDidEndEditingNotification,
            object: source
        ).sink { _ in
            endNotificationCount += 1
            XCTAssertNil(fixture.harness.nameEditing.draft,
                         "This callback must exercise the handoff after the previous draft was cleared")
            XCTAssertFalse(fixture.harness.actions.isPerforming,
                           "The file operation must still be finishing its previous name")
            other.selectText(nil)
            otherCoordinator.requestEditing()
            XCTAssertNil(fixture.harness.nameEditing.draft)
            XCTAssertNil(other.currentEditor(), "The end notification must not open a new native editor")
        }
        defer { observer.cancel() }

        let deletionButtons = try await operationButtons(in: host)
        let deletion = try XCTUnwrap(deletionButtons.first {
            $0.text.contains(String(localized: NewFileTemplatesText.delete))
        })
        XCTAssertTrue(deletion.press())
        await gate.waitUntilRemoving()
        XCTAssertEqual(endNotificationCount, 1)
        XCTAssertNil(fixture.harness.nameEditing.draft)
        XCTAssertNil(other.currentEditor())
        XCTAssertEqual(fixture.harness.saved, [
            NewFileTemplatesNativeSave(target: fixture.firstName, value: "Save then delete"),
        ])
        XCTAssertEqual(gate.ids, [fixture.firstName.templateID])
        gate.finish()
        for _ in 0..<100 {
            if fixture.harness.removedIDs == [fixture.firstName.templateID],
               !fixture.harness.actions.isPerforming { break }
            await Task.yield()
        }
        XCTAssertEqual(fixture.harness.removalAttempts, [fixture.firstName.templateID])
        XCTAssertEqual(fixture.harness.removedIDs, [fixture.firstName.templateID])
        XCTAssertNil(fixture.harness.nameEditing.draft)
        XCTAssertNil(other.currentEditor())
    }

    func testAddingAndReplacingKeepExistingRowsVisuallyStableDuringTheOperation() async throws {
        for action in [NewFileTemplatesNativeMutation.add, .replace] {
            let fixture = try NewFileTemplateSettingsPageFixture()
            let gate = NewFileTemplatesNativeActionGate()
            fixture.harness.importBoundary = { try await gate.perform() }
            fixture.harness.replacementBoundary = { _ in try await gate.perform() }
            let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
            defer {
                gate.finish()
                host.close()
            }
            let first = try await field(for: fixture.firstName, in: host)
            let second = try await field(for: fixture.secondName, in: host)
            let original = fixture.harness.templates
            let originalFields = nativeFields(in: host.view)
            let originalColors = originalFields.map(\.textColor)
            let title = action == .add ? NewFileTemplatesText.add : NewFileTemplatesText.replace
            let triggerButtons = try await operationButtons(in: host)
            let trigger = try XCTUnwrap(triggerButtons.first {
                $0.text.contains(String(localized: title))
            })
            XCTAssertTrue(trigger.press())
            await gate.waitUntilPerforming()
            host.layout()
            XCTAssertTrue(fixture.harness.isUpdating)
            XCTAssertEqual(fixture.harness.templates, original)
            XCTAssertTrue(originalFields.allSatisfy(\.isEnabled))
            XCTAssertEqual(originalFields.map(\.textColor), originalColors)
            XCTAssertEqual(nativeFields(in: host.view).map(ObjectIdentifier.init), originalFields.map(ObjectIdentifier.init))
            XCTAssertTrue(accessibilityElements(in: host.view).filter { $0.role == .button }.allSatisfy(\.isEnabled))
            XCTAssertFalse(accessibilityElements(in: host.view).contains { $0.role == .progressIndicator })
            XCTAssertTrue(trigger.press())
            await Task.yield()
            XCTAssertEqual(gate.callCount, 1)

            gate.finish()
            for _ in 0..<100 {
                if !fixture.harness.isUpdating,
                   fixture.harness.actions.allowsNameEditing(fixture.firstName, in: fixture.harness.nameEditing) { break }
                await Task.yield()
            }
            XCTAssertFalse(fixture.harness.isUpdating)
            first.selectText(nil)
            try await assertEditing(fixture.firstName, field: first, host: host)
            assertIdentity(first, target: fixture.firstName, in: host)
            assertIdentity(second, target: fixture.secondName, in: host)
            switch action {
            case .add:
                XCTAssertEqual(fixture.harness.importCount, 1)
                XCTAssertEqual(Array(fixture.harness.templates.prefix(original.count)), original)
                XCTAssertEqual(fixture.harness.templates.count, original.count + 1)
            case .replace:
                XCTAssertEqual(fixture.harness.replacedIDs, [fixture.firstName.templateID])
                XCTAssertEqual(fixture.harness.templates, original)
            }
        }
    }

    func testFailedDeletionPreservesRowsAndReleasesTheLockForRetry() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let gate = NewFileTemplatesNativeRemovalGate()
        fixture.harness.removalBoundary = { try await gate.remove($0) }
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
        defer {
            gate.finish()
            host.close()
        }
        let first = try await field(for: fixture.firstName, in: host)
        let retained = try await field(for: fixture.secondName, in: host)
        let original = fixture.harness.templates
        let deletionButtons = try await operationButtons(in: host)
        let deletion = try XCTUnwrap(deletionButtons.first {
            $0.text.contains(String(localized: NewFileTemplatesText.delete))
        })
        XCTAssertTrue(deletion.press())
        await gate.waitUntilRemoving()
        gate.finish(.failure(NewFileTemplatesNativeRemovalError.expected))
        try await dismissOperationError(in: host)
        XCTAssertEqual(fixture.harness.templates, original)
        XCTAssertTrue(fixture.harness.removedIDs.isEmpty)
        XCTAssertFalse(fixture.harness.isUpdating)
        assertIdentity(first, target: fixture.firstName, in: host)
        assertIdentity(retained, target: fixture.secondName, in: host)

        fixture.harness.removalBoundary = nil
        let retryButtons = try await operationButtons(in: host)
        let retry = try XCTUnwrap(retryButtons.first {
            $0.text.contains(String(localized: NewFileTemplatesText.delete))
        })
        XCTAssertTrue(retry.press())
        for _ in 0..<100 {
            if fixture.harness.removedIDs == [fixture.firstName.templateID] { break }
            await Task.yield()
        }
        XCTAssertEqual(fixture.harness.removalAttempts, [fixture.firstName.templateID, fixture.firstName.templateID])
        XCTAssertEqual(fixture.harness.removedIDs, [fixture.firstName.templateID])
        XCTAssertEqual(fixture.harness.templates, original.filter { $0.id != fixture.firstName.templateID })
        assertIdentity(retained, target: fixture.secondName, in: host)
    }

    func testBlankAndFieldClicksKeepTheLastDestinationWhileSaving() async throws {
        for finishLast in [false, true] {
            let fixture = try NewFileTemplateSettingsPageFixture()
            let gate = NewFileTemplatesNativeSaveGate()
            fixture.harness.saveBoundary = { try await gate.save($0) }
            let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
            defer {
                gate.finish()
                host.close()
            }
            let first = try await field(for: fixture.firstName, in: host)
            let middle = try await field(for: fixture.firstFileName, in: host)
            let latest = try await field(for: fixture.secondName, in: host)
            try click(first, in: host)
            try await assertEditing(fixture.firstName, field: first, host: host)
            try typeIntoFirstResponder("Save before final click", in: host)
            let originalEditor = try XCTUnwrap(first.currentEditor())
            try click(middle, in: host)
            await gate.waitUntilSaving()

            if finishLast {
                try click(latest, in: host)
                try clickBlank(.belowLastRow, in: host)
            } else {
                try clickBlank(.belowLastRow, in: host)
                try click(latest, in: host)
            }
            gate.finish()
            if finishLast {
                for _ in 0..<100 {
                    if fixture.harness.nameEditing.draft == nil,
                       !fixture.harness.nameEditing.isTransitioning { break }
                    await Task.yield()
                }
                XCTAssertNil(fixture.harness.nameEditing.draft)
                XCTAssertNil(first.currentEditor())
                XCTAssertNil(latest.currentEditor())
                XCTAssertFalse(host.window.firstResponder === originalEditor)
            } else {
                try await assertEditing(fixture.secondName, field: latest, host: host)
                try typeIntoFirstResponder("The last field wins", in: host)
                XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "The last field wins")
            }
            XCTAssertEqual(gate.values, [
                NewFileTemplatesNativeSave(target: fixture.firstName, value: "Save before final click"),
            ])
        }
    }

    func testBlankAreasCommitTheNameAndReleaseTheNativeEditor() async throws {
        for area in [NewFileTemplatesBlankArea.belowLastRow, .outerMargin, .footer] {
            let fixture = try NewFileTemplateSettingsPageFixture()
            let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
            defer { host.close() }
            let name = try await field(for: fixture.firstName, in: host)
            try click(name, in: host)
            try await assertEditing(fixture.firstName, field: name, host: host)
            try typeIntoFirstResponder("Saved from blank", in: host)
            let editor = try XCTUnwrap(name.currentEditor())
            try clickBlank(area, in: host)
            for _ in 0..<100 {
                if fixture.harness.nameEditing.draft == nil, !fixture.harness.nameEditing.isTransitioning { break }
                await Task.yield()
            }
            XCTAssertNil(fixture.harness.nameEditing.draft, "Clicking \(area) must finish the name edit")
            XCTAssertNil(name.currentEditor())
            XCTAssertFalse(host.window.firstResponder === editor)
            XCTAssertEqual(fixture.harness.saved, [
                NewFileTemplatesNativeSave(target: fixture.firstName, value: "Saved from blank"),
            ])
            assertIdentity(name, target: fixture.firstName, in: host)
        }
    }

    func testBlankClickWithInvalidInputKeepsOriginalTextAndNativeFocus() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
        defer { host.close() }
        let name = try await field(for: fixture.firstName, in: host)
        try click(name, in: host)
        try await assertEditing(fixture.firstName, field: name, host: host)
        try typeIntoFirstResponder("  ", in: host)
        try clickBlank(.belowLastRow, in: host)
        for _ in 0..<100 {
            if fixture.harness.nameEditing.draft?.errorMessage != nil,
               !fixture.harness.nameEditing.isTransitioning { break }
            await Task.yield()
        }
        try await assertEditing(fixture.firstName, field: name, host: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "  ")
        XCTAssertNotNil(fixture.harness.nameEditing.draft?.errorMessage)
        XCTAssertTrue(fixture.harness.saved.isEmpty)
        try typeIntoFirstResponder("Corrected after blank click", in: host)
        XCTAssertEqual(fixture.harness.nameEditing.draft?.value, "Corrected after blank click")
    }

    func testFileOperationSaveFailureKeepsOriginalNativeFocusAndDoesNotRunOperation() async throws {
        let fixture = try NewFileTemplateSettingsPageFixture()
        let host = NewFileTemplatesNativePageHost(harness: fixture.harness)
        defer { host.close() }
        let name = try await field(for: fixture.firstName, in: host)
        try click(name, in: host)
        try await assertEditing(fixture.firstName, field: name, host: host)
        try typeIntoFirstResponder("  ", in: host)
        let openButtons = try await operationButtons(in: host)
        let open = try XCTUnwrap(openButtons.first {
            $0.text.contains(String(localized: NewFileTemplatesText.open))
        })
        let frame = open.frame
        XCTAssertFalse(frame.isEmpty, "The Open button must have a real accessible frame")
        let windowPoint = host.window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        let hostPoint = host.view.convert(windowPoint, from: nil)
        let hit = try hitView(at: hostPoint, in: host)
        XCTAssertFalse(hit is FileTemplateEditingBackgroundView,
                       "The editing background must not cover the Open button")
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

    /// 隐藏宿主通过提示框的公开错误绑定确认失败，系统弹窗展示留给实际窗口验收。
    private func dismissOperationError(in host: NewFileTemplatesNativePageHost) async throws {
        for _ in 0..<100 {
            if let message = host.harness.actions.errorMessage {
                XCTAssertFalse(message.isEmpty)
                host.harness.actions.errorMessage = nil
                return
            }
            await Task.yield()
        }
        XCTFail("A failed deletion must publish an operation error before it can be acknowledged")
    }

    private func assertIdentity(_ field: FileTemplateNameNativeField, target: FileTemplateNameTarget, in host: NewFileTemplatesNativePageHost) {
        host.layout()
        XCTAssertTrue(nativeFields(in: host.view).first(where: { $0.editingCoordinator?.target == target }) === field,
                      "A name field must preserve its native view identity across edits")
    }

    private func field(for target: FileTemplateNameTarget, in host: NewFileTemplatesNativePageHost) async throws -> FileTemplateNameNativeField {
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

    private func click(_ field: FileTemplateNameNativeField, in host: NewFileTemplatesNativePageHost) throws {
        host.layout()
        let point = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: host.view)
        let hit = try hitView(at: point, in: host)
        XCTAssertTrue(hit === field, "The name field must receive its own hit-tested mouse down; received \(type(of: hit))")
        try mouseDown(on: hit, at: point, in: host)
    }

    private func clickBlank(_ area: NewFileTemplatesBlankArea, in host: NewFileTemplatesNativePageHost) throws {
        host.layout()
        let point: NSPoint
        switch area {
        case .belowLastRow:
            let scrollView = try XCTUnwrap(descendants(in: host.view).compactMap { $0 as? NSScrollView }.first)
            let viewport = scrollView.contentView.convert(scrollView.contentView.bounds, to: host.view)
            let fieldFrames = nativeFields(in: host.view).map { $0.convert($0.bounds, to: host.view) }
            if host.view.isFlipped {
                let lastFieldEdge = try XCTUnwrap(fieldFrames.map(\.maxY).max())
                point = NSPoint(x: viewport.midX, y: (lastFieldEdge + viewport.maxY) / 2)
            } else {
                let lastFieldEdge = try XCTUnwrap(fieldFrames.map(\.minY).min())
                point = NSPoint(x: viewport.midX, y: (viewport.minY + lastFieldEdge) / 2)
            }
        case .outerMargin:
            point = NSPoint(x: 2, y: host.view.bounds.midY)
        case .footer:
            point = NSPoint(x: host.view.bounds.maxX - 40,
                            y: host.view.isFlipped ? host.view.bounds.maxY - 24 : 24)
        }
        let hit = try hitView(at: point, in: host)
        XCTAssertTrue(hit is FileTemplateEditingBackgroundView,
                      "Blank \(area) must reach the editing background; received \(type(of: hit)) at \(point)")
        try mouseDown(on: hit, at: point, in: host)
    }

    private func descendants(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }

    private func hitView(at hostPoint: NSPoint, in host: NewFileTemplatesNativePageHost) throws -> NSView {
        let parentPoint = host.view.convert(hostPoint, to: host.view.superview)
        return try XCTUnwrap(host.view.hitTest(parentPoint), "The hosted page must hit-test its own content")
    }

    private func mouseDown(on hit: NSView, at hostPoint: NSPoint, in host: NewFileTemplatesNativePageHost) throws {
        let windowPoint = host.view.convert(hostPoint, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: windowPoint, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        hit.mouseDown(with: event)
    }

    private func assertEditing(_ target: FileTemplateNameTarget, field: FileTemplateNameNativeField, host: NewFileTemplatesNativePageHost,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if host.harness.nameEditing.draft?.target == target, !host.harness.nameEditing.isTransitioning { break }
            await Task.yield()
        }
        host.layout()
        XCTAssertEqual(host.harness.nameEditing.draft?.target, target, file: file, line: line)
        XCTAssertFalse(host.harness.nameEditing.isTransitioning, file: file, line: line)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView, "Target field must own the native field editor", file: file, line: line)
        XCTAssertTrue(host.window.firstResponder === editor, "Visible editing state must correspond to the native first responder", file: file, line: line)
        XCTAssertTrue(editor.isEditable, file: file, line: line)
    }

    private func typeIntoFirstResponder(_ text: String, in host: NewFileTemplatesNativePageHost) throws {
        let editor = try XCTUnwrap(host.window.firstResponder as? NSTextView)
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        XCTAssertEqual(editor.string, text)
    }

    /// 原生字段创建完成后，SwiftUI 的可访问性按钮树仍可能等待下一次主循环发布。
    private func operationButtons(
        in host: NewFileTemplatesNativePageHost,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [NewFileTemplatesNativeAccessibilityElement] {
        let titles = [NewFileTemplatesText.open, NewFileTemplatesText.replace, NewFileTemplatesText.delete, NewFileTemplatesText.add]
            .map { String(localized: $0) }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while true {
            host.layout()
            let buttons = accessibilityElements(in: host.view).filter { $0.role == .button }
            let matches = titles.compactMap { title in
                buttons.first { $0.text.contains(title) }
            }
            if matches.count == titles.count { return matches }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                let missing = titles.filter { title in !buttons.contains { $0.text.contains(title) } }
                return try XCTUnwrap(
                    nil as [NewFileTemplatesNativeAccessibilityElement]?,
                    "Timed out waiting for template file-operation buttons. Missing: \(missing); observed button text: \(buttons.map(\.text))",
                    file: file, line: line
                )
            }
            await withCheckedContinuation { continuation in
                RunLoop.main.perform { continuation.resume() }
            }
        }
    }

    private func accessibilityElements(in root: NSView) -> [NewFileTemplatesNativeAccessibilityElement] {
        var visited: Set<ObjectIdentifier> = []
        func visit(_ element: NewFileTemplatesNativeAccessibilityElement) -> [NewFileTemplatesNativeAccessibilityElement] {
            guard visited.insert(element.identity).inserted else { return [] }
            return [element] + element.children.flatMap(visit)
        }
        return visit(NewFileTemplatesNativeAccessibilityElement(object: root))
    }
}

@MainActor
private struct NewFileTemplateSettingsPageFixture {
    let harness: NewFileTemplatesNativePageHarness
    let firstName: FileTemplateNameTarget
    let firstFileName: FileTemplateNameTarget
    let secondName: FileTemplateNameTarget

    init() throws {
        let first = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        let second = try FileTemplate(displayName: "MD", defaultFileName: "untitled.md")
        harness = NewFileTemplatesNativePageHarness(templates: [first, second])
        firstName = .init(templateID: first.id, field: .displayName)
        firstFileName = .init(templateID: first.id, field: .defaultFileName)
        secondName = .init(templateID: second.id, field: .displayName)
    }
}

nonisolated private struct NewFileTemplatesNativeSave: Equatable {
    let target: FileTemplateNameTarget
    let value: String
}

@MainActor
private final class NewFileTemplatesNativePageHarness: ObservableObject {
    let nameEditing = FileTemplateNameEditingSession()
    let actions = FileTemplatePageActions()
    @Published private(set) var templates: [FileTemplate]
    @Published private(set) var isUpdating = false
    private(set) var saved: [NewFileTemplatesNativeSave] = []
    private(set) var openedIDs: [FileTemplateID] = []
    private(set) var replacedIDs: [FileTemplateID] = []
    private(set) var importCount = 0
    private(set) var removalAttempts: [FileTemplateID] = []
    private(set) var removedIDs: [FileTemplateID] = []
    var removalBoundary: ((FileTemplateID) async throws -> Void)?
    var replacementBoundary: ((FileTemplateID) async throws -> Void)?
    var importBoundary: (() async throws -> Void)?
    var saveBoundary: ((NewFileTemplatesNativeSave) async throws -> Void)?

    init(templates: [FileTemplate]) { self.templates = templates }
    func open(_ id: FileTemplateID) { openedIDs.append(id) }
    func replace(_ id: FileTemplateID) async throws {
        isUpdating = true
        defer { isUpdating = false }
        try await replacementBoundary?(id)
        replacedIDs.append(id)
        templates = Array(templates)
    }

    func importTemplate() async throws {
        importCount += 1
        isUpdating = true
        defer { isUpdating = false }
        try await importBoundary?()
        templates.append(try FileTemplate(displayName: "Imported", defaultFileName: "imported.bin"))
    }

    func remove(_ id: FileTemplateID) async throws {
        removalAttempts.append(id)
        isUpdating = true
        defer { isUpdating = false }
        try await removalBoundary?(id)
        let position = try XCTUnwrap(templates.firstIndex { $0.id == id })
        templates.remove(at: position)
        removedIDs.append(id)
    }

    func update(_ id: FileTemplateID, field: FileTemplateNameField, value: String) async throws {
        let change = NewFileTemplatesNativeSave(target: .init(templateID: id, field: field), value: value)
        isUpdating = true
        defer { isUpdating = false }
        try await saveBoundary?(change)
        let position = try XCTUnwrap(templates.firstIndex { $0.id == id })
        templates[position] = try field.updating(templates[position], to: value)
        saved.append(change)
    }
}

@MainActor
private struct NewFileTemplatesNativePageContent: View {
    @ObservedObject var harness: NewFileTemplatesNativePageHarness
    let pageID: UUID
    var body: some View {
        NewFileTemplateSettingsPage(
            state: .ready(harness.templates), isUpdating: harness.isUpdating,
            nameEditing: harness.nameEditing, actions: harness.actions,
            importTemplate: { try await harness.importTemplate() }, updateName: { try await harness.update($0, field: $1, value: $2) },
            openTemplate: { harness.open($0) }, replaceTemplate: { try await harness.replace($0) },
            removeTemplate: { try await harness.remove($0) }, reload: {}
        )
        .id(pageID)
    }
}

/// 隐藏窗口让字段使用 AppKit 共享编辑器，所有事件只发往测试自己的控件。
@MainActor
private final class NewFileTemplatesNativePageHost {
    let harness: NewFileTemplatesNativePageHarness
    let view: NSHostingView<NewFileTemplatesNativePageContent>
    let window: NSWindow

    init(harness: NewFileTemplatesNativePageHarness) {
        self.harness = harness
        let frame = NSRect(x: 0, y: 0, width: 720, height: 420)
        view = NSHostingView(rootView: NewFileTemplatesNativePageContent(harness: harness, pageID: UUID()))
        view.frame = frame
        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = view
        layout()
    }
    func layout() { view.layoutSubtreeIfNeeded() }
    func rebuildPage() {
        view.rootView = NewFileTemplatesNativePageContent(harness: harness, pageID: UUID())
        layout()
    }
    func close() {
        harness.nameEditing.cancelEditing()
        window.contentView = nil
        window.close()
    }
}

@MainActor
private final class NewFileTemplatesNativeSaveGate {
    private(set) var values: [NewFileTemplatesNativeSave] = []
    private var entered: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Error>?
    func save(_ value: NewFileTemplatesNativeSave) async throws {
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
private struct NewFileTemplatesNativeAccessibilityElement {
    let object: AnyObject
    var identity: ObjectIdentifier { ObjectIdentifier(object) }
    var role: NSAccessibility.Role? { object.accessibilityRole?() }
    var frame: NSRect { object.accessibilityFrame?() ?? .zero }
    var isEnabled: Bool { object.isAccessibilityEnabled?() ?? false }
    func press() -> Bool { object.accessibilityPerformPress?() ?? false }
    var text: [String] {
        let value: Any? = object.accessibilityValue?()
        return [object.accessibilityLabel?(), object.accessibilityTitle?(), value as? String]
            .compactMap { $0 }
    }
    var children: [NewFileTemplatesNativeAccessibilityElement] {
        let children: [Any] = object.accessibilityChildren?() ?? []
        return children.map { NewFileTemplatesNativeAccessibilityElement(object: $0 as AnyObject) }
    }
}

private enum NewFileTemplatesBlankArea {
    case belowLastRow
    case outerMargin
    case footer
}

@MainActor
private final class NewFileTemplatesNativeRemovalGate {
    private(set) var ids: [FileTemplateID] = []
    private var entered: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Error>?

    func remove(_ id: FileTemplateID) async throws {
        ids.append(id)
        guard ids.count == 1 else {
            XCTFail("An in-flight deletion must reject repeated file actions")
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            entered?.resume()
            entered = nil
        }
    }

    func waitUntilRemoving() async {
        if completion != nil { return }
        await withCheckedContinuation { entered = $0 }
    }

    func finish(_ result: Result<Void, Error> = .success(())) {
        completion?.resume(with: result)
        completion = nil
    }
}

private enum NewFileTemplatesNativeRemovalError: Error {
    case expected
}

private enum NewFileTemplatesNativeMutation {
    case add
    case replace
}

@MainActor
private final class NewFileTemplatesNativeActionGate {
    private(set) var callCount = 0
    private var entered: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Error>?

    func perform() async throws {
        callCount += 1
        guard callCount == 1 else {
            XCTFail("An in-flight file operation must reject repeated actions")
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            entered?.resume()
            entered = nil
        }
    }

    func waitUntilPerforming() async {
        if completion != nil { return }
        await withCheckedContinuation { entered = $0 }
    }

    func finish() {
        completion?.resume()
        completion = nil
    }
}

import Foundation
import XCTest
@testable import ECMenu

@MainActor
final class FileTemplateNameEditingSessionTests: XCTestCase {
    func testUnchangedSwitchHandsOffSynchronouslyWithNoSaveAndIgnoresOldEndNotification() async {
        let session = FileTemplateNameEditingSession()
        let first = NameControlSpy(value: "TXT")
        let second = NameControlSpy(value: "untitled.txt")
        var saved: [String] = []
        let firstOpened = await session.requestEditing(first) { saved.append($0) }.value
        XCTAssertTrue(firstOpened)
        first.didFinish = { [weak first] in
            if let first { session.editingDidEnd(first) }
        }

        let secondOpened = await session.requestEditing(second) { saved.append($0) }.value
        XCTAssertTrue(secondOpened)
        XCTAssertTrue(session.isEditing(second))
        XCTAssertFalse(session.isEditing(first))
        XCTAssertEqual(first.finishedValues, ["TXT"])
        XCTAssertEqual(second.begunValues, ["untitled.txt"])
        XCTAssertTrue(saved.isEmpty)
        session.editingDidEnd(first)
        XCTAssertTrue(session.isEditing(second))
        XCTAssertFalse(session.isTransitioning)
    }

    func testLatestTargetWinsWhileOneSaveIsSuspended() async {
        let session = FileTemplateNameEditingSession()
        let first = NameControlSpy(value: "TXT")
        let middle = NameControlSpy(value: "untitled.txt")
        let latest = NameControlSpy(value: "Other")
        let gate = NameSessionSaveGate()
        defer { gate.finish() }
        _ = await session.requestEditing(first) { try await gate.save($0) }.value
        first.displayedValue = "Changed"
        session.valueDidChange("Changed", from: first)

        let middleRequest = session.requestEditing(middle) { _ in }
        await gate.waitUntilSaving()
        let latestRequest = session.requestEditing(latest) { _ in }
        XCTAssertTrue(session.isTransitioning)
        XCTAssertTrue(session.isEditing(first))
        XCTAssertEqual(first.inputEnabled.last, false)
        XCTAssertTrue(middle.begunValues.isEmpty)
        XCTAssertTrue(latest.begunValues.isEmpty)
        gate.finish()

        let middleResult = await middleRequest.value
        let latestResult = await latestRequest.value
        XCTAssertFalse(middleResult)
        XCTAssertTrue(latestResult)
        XCTAssertTrue(session.isEditing(latest))
        XCTAssertFalse(session.isTransitioning)
        XCTAssertTrue(middle.begunValues.isEmpty)
        XCTAssertEqual(latest.begunValues, ["Other"])
        XCTAssertEqual(gate.values, ["Changed"])
        XCTAssertEqual(first.finishedValues, ["Changed"])
    }

    func testFailedSaveRestoresOriginalControlAndInputCanBeCorrectedBeforeRetry() async {
        let session = FileTemplateNameEditingSession()
        let first = NameControlSpy(value: "TXT")
        let second = NameControlSpy(value: "untitled.txt")
        var saved: [String] = []
        _ = await session.requestEditing(first) { value in
            saved.append(value)
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FileTemplateValidationError.emptyDisplayName
            }
        }.value
        first.displayedValue = "  "
        session.valueDidChange("  ", from: first)
        let failed = await session.requestEditing(second) { _ in }.value
        XCTAssertFalse(failed)
        XCTAssertTrue(session.isEditing(first))
        XCTAssertFalse(session.isTransitioning)
        XCTAssertEqual(session.draft?.value, "  ")
        XCTAssertNotNil(session.draft?.errorMessage)
        XCTAssertEqual(first.begunValues, ["TXT", "  "])
        XCTAssertTrue(second.begunValues.isEmpty)

        first.displayedValue = "Corrected"
        session.valueDidChange("Corrected", from: first)
        let retried = await session.requestEditing(second) { _ in }.value
        XCTAssertTrue(retried)
        XCTAssertTrue(session.isEditing(second))
        XCTAssertEqual(saved, ["  ", "Corrected"])
        XCTAssertEqual(first.finishedValues, ["Corrected"])
    }

    func testFailedSaveRestorationIgnoresTheNativeEndNotificationDuringReentry() async {
        let session = FileTemplateNameEditingSession()
        let first = NameControlSpy(value: "TXT")
        let second = NameControlSpy(value: "untitled.txt")
        var attempts: [String] = []
        _ = await session.requestEditing(first) { value in
            attempts.append(value)
            throw FileTemplateValidationError.emptyDisplayName
        }.value
        first.displayedValue = "  "
        first.didBegin = { [weak first] in
            if let first { session.editingDidEnd(first) }
        }
        let result = await session.requestEditing(second) { _ in }.value
        XCTAssertFalse(result)
        XCTAssertTrue(session.isEditing(first))
        XCTAssertFalse(session.isTransitioning)
        XCTAssertEqual(attempts, ["  "])
        XCTAssertEqual(first.begunValues, ["TXT", "  "])
        XCTAssertTrue(second.begunValues.isEmpty)
    }

    func testLatestFieldEditorValueIsCommittedEvenBeforeChangeNotificationArrives() async {
        let session = FileTemplateNameEditingSession()
        let first = NameControlSpy(value: "TXT")
        let second = NameControlSpy(value: "untitled.txt")
        var saved: [String] = []
        _ = await session.requestEditing(first) { saved.append($0) }.value
        first.displayedValue = "Latest editor text"
        _ = await session.requestEditing(second) { _ in }.value
        XCTAssertEqual(saved, ["Latest editor text"])
        XCTAssertTrue(session.isEditing(second))
    }

    func testCancelRestoresOriginalValueWithoutSaving() async {
        let session = FileTemplateNameEditingSession()
        let control = NameControlSpy(value: "TXT")
        var saved: [String] = []
        _ = await session.requestEditing(control) { saved.append($0) }.value
        control.displayedValue = "Draft"
        session.valueDidChange("Draft", from: control)
        session.cancelEditing()
        XCTAssertNil(session.draft)
        XCTAssertEqual(control.finishedValues, ["TXT"])
        XCTAssertTrue(saved.isEmpty)
    }
}

@MainActor
private final class NameControlSpy: FileTemplateNameControl {
    let target = FileTemplateNameTarget(templateID: FileTemplateID(), field: .displayName)
    var displayedValue: String
    var didFinish: (() -> Void)?
    var didBegin: (() -> Void)?
    private(set) var begunValues: [String] = []
    private(set) var finishedValues: [String] = []
    private(set) var inputEnabled: [Bool] = []

    init(value: String) { displayedValue = value }
    func prepareToCommit() -> String { displayedValue }
    func beginEditing(_ value: String) {
        displayedValue = value
        begunValues.append(value)
        inputEnabled.append(true)
        didBegin?()
    }
    func finishEditing(_ value: String) {
        displayedValue = value
        finishedValues.append(value)
        didFinish?()
    }
    func setInputEnabled(_ enabled: Bool) { inputEnabled.append(enabled) }
}

@MainActor
private final class NameSessionSaveGate {
    private(set) var values: [String] = []
    private var entered: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Error>?

    func save(_ value: String) async throws {
        values.append(value)
        guard values.count == 1 else {
            XCTFail("The same name draft was saved more than once")
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

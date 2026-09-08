/**
 验证单个模板名称草稿的校验失败恢复、提交去重与重试。
 用并发提交模拟回车和失焦的重复请求，并检查未修改输入直接结束编辑。
 */

import Foundation
import XCTest
@testable import ECMenu

@MainActor
final class FileTemplateNameDraftTests: XCTestCase {
    /// 回车与失焦在同一次保存期间到达时，都等待相同的保存结果。
    func testConcurrentCommitsShareOneSaveAndLaterCommitsDoNotSaveAgain() async throws {
        let template = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        let save = FileTemplateDraftSaveGate()
        let draft = FileTemplateNameDraft(target: .init(templateID: template.id, field: .displayName), value: template.displayName) {
            try await save.save($0)
        }
        draft.value = "Notes"
        let first = Task { await draft.commit() }
        await save.entered.wait()
        XCTAssertTrue(draft.isSaving)
        XCTAssertEqual(save.values, ["Notes"])

        let duplicateEntered = FileTemplateDraftSignal()
        let duplicate = Task {
            duplicateEntered.signal()
            return await draft.commit()
        }
        await duplicateEntered.wait()
        XCTAssertTrue(draft.isSaving)
        XCTAssertEqual(save.values, ["Notes"])
        save.finish(.success(()))

        let firstResult = await first.value
        let duplicateResult = await duplicate.value
        XCTAssertTrue(firstResult)
        XCTAssertTrue(duplicateResult)
        XCTAssertFalse(draft.isSaving)
        XCTAssertNil(draft.errorMessage)
        let laterResult = await draft.commit()
        XCTAssertTrue(laterResult)
        XCTAssertEqual(save.values, ["Notes"])
    }

    func testUnchangedInputFinishesWithoutSaving() async throws {
        let template = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        for field in [FileTemplateNameField.displayName, .defaultFileName] {
            var savedValues: [String] = []
            let draft = FileTemplateNameDraft(target: .init(templateID: template.id, field: field), value: field.value(in: template)) {
                savedValues.append($0)
            }
            XCTAssertEqual(draft.target, FileTemplateNameTarget(templateID: template.id, field: field))
            XCTAssertEqual(draft.value, field.value(in: template))
            let initialResult = await draft.commit()
            let duplicateResult = await draft.commit()
            XCTAssertTrue(initialResult)
            XCTAssertTrue(duplicateResult)
            XCTAssertEqual(savedValues, [])
            XCTAssertNil(draft.errorMessage)
            XCTAssertFalse(draft.isSaving)
        }
    }

    /// 校验失败不能吞掉输入；修正后的重试清除错误并提交修正值。
    func testValidationFailureKeepsInputAndAllowsCorrectedRetry() async throws {
        let template = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        let scenarios: [(FileTemplateNameField, String, String)] = [
            (.displayName, "   ", "Text"),
            (.defaultFileName, "folder/new.txt", "new.txt"),
        ]
        for (field, invalid, corrected) in scenarios {
            var attemptedValues: [String] = []
            var saved: [FileTemplate] = []
            let draft = FileTemplateNameDraft(target: .init(templateID: template.id, field: field), value: field.value(in: template)) { value in
                attemptedValues.append(value)
                saved.append(try field.updating(template, to: value))
            }
            draft.value = invalid
            let failed = await draft.commit()
            XCTAssertFalse(failed)
            XCTAssertEqual(draft.value, invalid)
            XCTAssertFalse(draft.isSaving)
            XCTAssertFalse(try XCTUnwrap(draft.errorMessage).isEmpty)
            XCTAssertTrue(saved.isEmpty)

            draft.value = corrected
            let retried = await draft.commit()
            XCTAssertTrue(retried)
            XCTAssertEqual(draft.value, corrected)
            XCTAssertNil(draft.errorMessage)
            XCTAssertFalse(draft.isSaving)
            XCTAssertEqual(attemptedValues, [invalid, corrected])
            XCTAssertEqual(saved, [try field.updating(template, to: corrected)])
        }
    }
}

/// 单次信号允许先发出再等待，测试时序不依赖计时器或轮询。
@MainActor
private final class FileTemplateDraftSignal {
    private var signalled = false
    private var waiter: CheckedContinuation<Void, Never>?

    func signal() {
        precondition(!signalled)
        signalled = true
        waiter?.resume()
        waiter = nil
    }

    func wait() async {
        if signalled { return }
        precondition(waiter == nil)
        await withCheckedContinuation { waiter = $0 }
    }
}

@MainActor
private final class FileTemplateDraftSaveGate {
    let entered = FileTemplateDraftSignal()
    private(set) var values: [String] = []
    private var completion: CheckedContinuation<Void, Error>?

    func save(_ value: String) async throws {
        values.append(value)
        guard values.count == 1 else { throw FileTemplateDraftGateError.repeatedSave }
        try await withCheckedThrowingContinuation { continuation in
            precondition(completion == nil)
            completion = continuation
            entered.signal()
        }
    }

    func finish(_ result: Result<Void, Error>) {
        precondition(completion != nil)
        completion!.resume(with: result)
        completion = nil
    }
}

private enum FileTemplateDraftGateError: Error {
    case repeatedSave
}

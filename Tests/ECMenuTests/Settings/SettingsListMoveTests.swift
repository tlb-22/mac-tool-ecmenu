/**
 验证原生 List 移动下标转换为稳定模板或命令身份的业务意图。
 覆盖向上、向下、末尾与原位，不模拟系统拖拽或重复验证业务持久化。
 */

import XCTest
@testable import ECMenu

@MainActor
final class SettingsListMoveTests: XCTestCase {
    func testNativeMoveOffsetsIdentifyTheMovedItemAndItsFinalSuccessor() throws {
        let ids = ["a", "b", "c", "d"]
        let cases: [(source: Int, destination: Int, id: String, before: String?)] = [
            (3, 1, "d", "b"),
            (0, 3, "a", "d"),
            (1, 4, "b", nil),
            (2, 0, "c", "a"),
        ]
        for item in cases {
            let movement = try XCTUnwrap(SettingsListMove(
                ids: ids, source: IndexSet(integer: item.source), destination: item.destination
            ))
            XCTAssertEqual(movement.id, item.id)
            XCTAssertEqual(movement.before, item.before)
        }
    }

    func testDroppingOnEitherSideOfTheSameRowProducesNoSaveIntent() {
        let ids = ["a", "b", "c"]
        for destination in [1, 2] {
            XCTAssertNil(SettingsListMove(ids: ids, source: IndexSet(integer: 1), destination: destination))
        }
    }
}

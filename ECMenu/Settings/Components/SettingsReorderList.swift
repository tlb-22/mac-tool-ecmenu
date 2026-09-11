/**
 使用系统 List 管理整行拖动预览、插入指示、取消与边缘滚动。
 将原生 onMove 的最终下标转换为稳定 ID 意图，每次实际移动只调用一次业务保存入口。
 */

import SwiftUI

struct SettingsReorderList<Row: Identifiable, RowContent: View>: View {
    let rows: [Row]
    var allowsMoving = true
    var dragBegan: () -> Void = {}
    var dragEnded: () -> Void = {}
    let move: (Row.ID, Row.ID?) -> Void
    @ViewBuilder let rowContent: (Row) -> RowContent

    var body: some View {
        List {
            ForEach(rows) { row in
                rowContent(row)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(!allowsMoving)
            }
            .onMove { source, destination in
                if let movement = SettingsListMove(ids: rows.map(\.id), source: source, destination: destination) {
                    move(movement.id, movement.before)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.all, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 1)
        .onDragSessionUpdated { session in
            switch session.phase {
            case .initial: dragBegan()
            case .ended: dragEnded()
            default: break
            }
        }
    }
}

/// 单选列表的系统移动结果；原位放下不产生保存意图。
struct SettingsListMove<ID: Hashable>: Equatable {
    let id: ID
    let before: ID?

    init?(ids: [ID], source: IndexSet, destination: Int) {
        precondition(source.count == 1)
        let index = source.first!
        let destinationIndex = destination > index ? destination - 1 : destination
        guard destinationIndex != index else { return nil }
        var remaining = ids
        id = remaining.remove(at: index)
        before = destinationIndex < remaining.count ? remaining[destinationIndex] : nil
    }
}

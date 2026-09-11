/**
 显示设置行左侧的三线重排提示，并提供键盘与辅助功能的相邻移动入口。
 鼠标拖动由外层原生 List 接管，手柄不建立独立拖拽会话或图像。
 */

import SwiftUI

struct SettingsReorderHandle: View {
    let title: String
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 24)
            .help(Text("Drag to reorder"))
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: moveUp?()
                case .down: moveDown?()
                default: break
                }
            }
            .accessibilityLabel(Text("Reorder \(title)"))
            .accessibilityHint(Text("Drag to reorder. Use the Up and Down arrow keys to move this item."))
            .accessibilityActions {
                if let moveUp { Button("Move Up", action: moveUp) }
                if let moveDown { Button("Move Down", action: moveDown) }
            }
    }
}

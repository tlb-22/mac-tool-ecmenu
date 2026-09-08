/**
 把模板页面空白区域的原生鼠标事件接入名称编辑会话。
 在点击背景时结束当前编辑，并保持 AppKit 焦点行为可控。
 */

import SwiftUI

/// 背景只接收未命中前景控件的点击，字段和操作按钮保持自己的事件路径。
struct FileTemplateEditingBackground: NSViewRepresentable {
    let clicked: () -> Void

    func makeNSView(context: Context) -> FileTemplateEditingBackgroundView {
        FileTemplateEditingBackgroundView(clicked: clicked)
    }

    func updateNSView(_ view: FileTemplateEditingBackgroundView, context: Context) {
        view.clicked = clicked
    }
}

final class FileTemplateEditingBackgroundView: NSView {
    var clicked: () -> Void

    init(clicked: @escaping () -> Void) {
        self.clicked = clicked
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(clicked:)") }

    override func mouseDown(with event: NSEvent) {
        clicked()
    }
}

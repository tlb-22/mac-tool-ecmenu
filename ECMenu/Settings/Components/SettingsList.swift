/**
 统一设置页原生列表容器和行内容的呈现方式。
 系统管理列表布局，页面提供行与分割线，排序行为由排序列表另行接入。
 */

import SwiftUI

struct SettingsList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        List {
            content()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.all, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 1)
    }
}

/// 行内容和自绘分割线共享同一原生单元格边界。
struct SettingsListRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

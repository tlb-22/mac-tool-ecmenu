/**
 统一设置页原生列表容器和行内容的呈现方式。
 系统管理列表布局与分割线，页面提供行内容，排序行为由排序列表另行接入。
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

/// 各能力共用原生行边距、分割线与背景设置。
struct SettingsListRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.visible)
            .listRowBackground(Color.clear)
    }
}

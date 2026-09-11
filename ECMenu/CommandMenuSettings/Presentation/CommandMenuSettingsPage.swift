/**
 按用户顺序呈现命令手柄、菜单可见性开关与外部应用依赖状态。
 排序和开关分别发出变更意图，外部依赖只限制开关操作。
 */

import AppKit
import SwiftUI

/// 菜单配置页面只根据业务配置与系统事实呈现可操作状态。
struct CommandMenuSettingsPage: View {
    let descriptors: [ContextCommandDescriptor]
    let configuration: CommandMenuSettings
    let systemState: StatusPageSystemState
    let setVisibility: (Bool, ContextCommandFeatureID) -> Void
    let moveCommand: (ContextCommandFeatureID, ContextCommandFeatureID?) -> Void

    private var orderedDescriptors: [ContextCommandDescriptor] {
        configuration.orderedFeatureIDs.map { id in descriptors.first { $0.id == id }! }
    }

    /// 显示每项 Finder 右键命令的图标、外部依赖状态与开关。
    var body: some View {
        VStack {
            GroupBox {
                SettingsReorderList(rows: orderedDescriptors, move: moveCommand) { descriptor in
                    contextMenuRow(for: descriptor)
                }
                .frame(height: CGFloat(orderedDescriptors.count) * StatusPageStyle.rowHeight)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(StatusPageStyle.contentPadding)
    }

    /// 命令开关的交互规则由呈现层结合菜单配置与系统事实决定。
    static func isVisibilityEditable(
        for descriptor: ContextCommandDescriptor,
        configuration: CommandMenuSettings,
        systemState: StatusPageSystemState
    ) -> Bool {
        configuration.isEnabled && systemState.isDependencyAvailable(for: descriptor)
    }

    /// 构造一项右键命令设置行。
    /// - Parameter descriptor: 当前命令的共享产品声明。
    /// - Returns: 不读取系统状态的设置行。
    private func contextMenuRow(
        for descriptor: ContextCommandDescriptor
    ) -> some View {
        let isDependencyAvailable = systemState.isDependencyAvailable(for: descriptor)
        let visibilityTitle = StatusPageAccessibility.showCommand(descriptor.title)
        let dependencyStatus = isDependencyAvailable
            ? LocalizedStringResource(
                "statusPage.contextMenu.installed",
                defaultValue: "Installed",
                comment: "Status of a required external application"
            )
            : LocalizedStringResource(
                "statusPage.contextMenu.notInstalled",
                defaultValue: "Not Installed",
                comment: "Status of a missing required external application"
            )

        return SettingsComponents.settingRow {
            reorderHandle(for: descriptor)
            SettingsComponents.settingLabel(descriptor.title) {
                SettingsComponents.commandIcon(for: descriptor, systemState: systemState)
            }
            .foregroundStyle(
                isDependencyAvailable ? Color.primary : Color.secondary
            )
        } trailing: {
            HStack(spacing: StatusPageStyle.rowSpacing) {
                if descriptor.requiredApplication != nil {
                    Text(dependencyStatus)
                        .font(.caption)
                        .foregroundStyle(
                            isDependencyAvailable ? .green : .secondary
                        )
                }

                SettingsComponents.compactToggle(
                    visibilityTitle,
                    isOn: Binding(
                        get: { configuration.isVisible(descriptor.id) },
                        set: { isVisible in
                            setVisibility(isVisible, descriptor.id)
                        }
                    )
                )
                .disabled(
                    !Self.isVisibilityEditable(
                        for: descriptor,
                        configuration: configuration,
                        systemState: systemState
                    )
                )
            }
        }
    }

    private func reorderHandle(for descriptor: ContextCommandDescriptor) -> some View {
        let ids = configuration.orderedFeatureIDs
        let index = ids.firstIndex(of: descriptor.id)!
        return SettingsReorderHandle(
            title: String(localized: descriptor.title),
            moveUp: index > 0 ? { moveCommand(descriptor.id, ids[index - 1]) } : nil,
            moveDown: index + 1 < ids.count
                ? { moveCommand(descriptor.id, ids.dropFirst(index + 2).first) } : nil
        )
        .frame(width: 20, height: 24)
    }
}

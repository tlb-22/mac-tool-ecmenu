/**
 呈现各命令的菜单可见性开关与外部应用依赖状态。
 根据注入的配置和系统事实确定可操作性，通过回调请求变更。
 */

import AppKit
import SwiftUI

/// 菜单配置页面只根据业务配置与系统事实呈现可操作状态。
struct CommandMenuSettingsPage: View {
    let descriptors: [ContextCommandDescriptor]
    let configuration: CommandMenuSettings
    let systemState: StatusPageSystemState
    let setVisibility: (Bool, ContextCommandFeatureID) -> Void

    /// 显示每项 Finder 右键命令的图标、外部依赖状态与开关。
    var body: some View {
        ScrollView {
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(descriptors, id: \.id) { descriptor in
                        contextMenuRow(for: descriptor)

                        if descriptor.id != descriptors.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
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
        .disabled(!isDependencyAvailable)
    }

}

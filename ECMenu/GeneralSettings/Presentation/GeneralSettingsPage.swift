/**
 呈现产品总开关、登录启动、Finder 扩展与系统权限入口。
 根据注入的状态组织界面，通过回调请求配置变更和系统操作。
 */

import AppKit
import SwiftUI

/// 通用设置的产品状态与系统入口呈现。
struct GeneralSettingsPage: View {
    let displayName: String
    let configuration: CommandMenuSettings
    let systemState: StatusPageSystemState
    let loginItemState: LoginItemRegistrationState
    let setEnabled: (Bool) -> Void
    let setLoginItemRequested: (Bool) -> Void
    let manageExtension: () -> Void
    let openFullDiskAccessSettings: () -> Void

    /// 显示产品总开关与两个必要的系统设置入口。
    var body: some View {
        let enableTitle = LocalizedStringResource(
            "statusPage.general.enableApplication",
            defaultValue: "Enable \(displayName)",
            comment: "Label for the switch that enables the application's Finder commands"
        )
        let openAtLoginTitle = LocalizedStringResource(
            "statusPage.general.openAtLogin",
            defaultValue: "Open at Login",
            comment: "Label for the switch that starts the application at login"
        )

        return VStack(spacing: StatusPageStyle.sectionSpacing) {
            GroupBox {
                VStack(spacing: 0) {
                    SettingsComponents.settingRow {
                        SettingsComponents.settingLabel(enableTitle) {
                            SettingsComponents.systemRowIcon("power")
                        }
                        .foregroundStyle(
                            systemState.isExtensionEnabled
                                ? Color.primary
                                : Color.secondary
                        )
                    } trailing: {
                        SettingsComponents.compactToggle(
                            enableTitle,
                            isOn: Binding(
                                get: { configuration.isEnabled },
                                set: setEnabled
                            )
                        )
                    }
                    .disabled(!systemState.isExtensionEnabled)

                    Divider()

                    SettingsComponents.settingRow {
                        SettingsComponents.settingLabel(openAtLoginTitle) {
                            SettingsComponents.systemRowIcon("person")
                        }
                    } trailing: {
                        HStack(spacing: StatusPageStyle.rowSpacing) {
                            if let title = loginItemState.pendingApprovalTitle {
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            SettingsComponents.compactToggle(
                                openAtLoginTitle,
                                isOn: Binding(
                                    get: { loginItemState.isRequested },
                                    set: setLoginItemRequested
                                )
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            GroupBox {
                VStack(spacing: 0) {
                    SettingsComponents.settingRow {
                        SettingsComponents.settingLabel(
                            LocalizedStringResource(
                                "statusPage.general.finderExtension",
                                defaultValue: "Finder Extension",
                                comment: "Label for the Finder Extension settings row"
                            )
                        ) {
                            SettingsComponents.systemRowIcon("puzzlepiece.extension")
                            .foregroundStyle(
                                systemState.isExtensionEnabled ? .green : .secondary
                            )
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(
                            StatusPageAccessibility.extensionState(
                                isEnabled: systemState.isExtensionEnabled
                            )
                        )
                    } trailing: {
                        Button(
                            LocalizedStringResource(
                                "statusPage.general.settings",
                                defaultValue: "Settings…",
                                comment: "Button that opens a related pane in System Settings"
                            )
                        ) {
                            manageExtension()
                        }
                        .accessibilityLabel(
                            StatusPageAccessibility.extensionSettings
                        )
                    }

                    Divider()

                    SettingsComponents.settingRow {
                        SettingsComponents.settingLabel(
                            LocalizedStringResource(
                                "statusPage.general.fullDiskAccess",
                                defaultValue: "Full Disk Access",
                                comment: "Label for the Full Disk Access settings row"
                            )
                        ) {
                            SettingsComponents.systemRowIcon("folder.badge.person.crop")
                        }
                    } trailing: {
                        Button(
                            LocalizedStringResource(
                                "statusPage.general.settings",
                                defaultValue: "Settings…",
                                comment: "Button that opens a related pane in System Settings"
                            )
                        ) {
                            openFullDiskAccessSettings()
                        }
                        .accessibilityLabel(
                            StatusPageAccessibility.fullDiskAccessSettings
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(StatusPageStyle.contentPadding)
    }

}

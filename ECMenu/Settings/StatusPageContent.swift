/**
 定义配置窗口导航，并按注入状态组合菜单、模板和应用设置子页面。
 持有窗口内模板编辑与操作会话，协调页面切换和失去激活时的名称提交。
 */

import AppKit
import SwiftUI

/// 状态页左侧导航可以选择的产品设置分类。
enum StatusPagePane: String, CaseIterable, Identifiable {
    /// 软件总开关与系统权限入口。
    case general

    /// 每一项 Finder 右键命令的显示配置。
    case contextMenu

    /// 用户保存的普通文件模板。
    case newFileTemplates = "fileTemplates"

    /// SwiftUI 列表使用的稳定身份。
    var id: Self { self }

    /// 面向用户显示的分类名称。
    var title: LocalizedStringResource {
        switch self {
        case .general:
            LocalizedStringResource(
                "statusPage.pane.general",
                defaultValue: "General",
                comment: "Title of the general settings pane"
            )
        case .contextMenu:
            LocalizedStringResource(
                "statusPage.pane.contextMenu",
                defaultValue: "Context Menu",
                comment: "Title of the Finder context-menu settings pane"
            )
        case .newFileTemplates:
            LocalizedStringResource(
                "statusPage.pane.fileTemplates",
                defaultValue: "File Templates",
                comment: "Title of the file-template settings pane"
            )
        }
    }

    /// 左侧导航使用的 SF Symbol。
    var systemImageName: String {
        switch self {
        case .general:
            "gearshape"
        case .contextMenu:
            "contextualmenu.and.cursorarrow"
        case .newFileTemplates:
            "doc.on.doc"
        }
    }
}

/// 只根据注入的值和用户操作回调呈现主应用状态页。
///
/// 该类型不读取 Finder、Launch Services、偏好存储或分布式通知，
/// 因此产品容器和独立界面预览都可以复用同一呈现实现。
struct StatusPageContent: View {
    /// 页面显示的产品名称。
    let displayName: String

    /// 页面左侧显示的产品版本号。
    let version: String

    /// 当前选中的设置分类。
    @Binding var selectedPane: StatusPagePane

    /// 不含系统读写的 Extension 状态与外部应用快照。
    let systemState: StatusPageSystemState

    /// 主应用登录项当前的登记和系统批准状态。
    let loginItemState: LoginItemRegistrationState

    /// 全部右键命令的产品描述；页面根据配置排列显示顺序。
    let descriptors: [ContextCommandDescriptor]

    /// 当前产品总开关、菜单可见性与命令顺序快照。
    let configuration: CommandMenuSettings

    /// 模板库的读取结果与正在执行的持久化操作。
    let fileTemplateState: FileTemplatePageState
    let isUpdatingNewFileTemplates: Bool

    /// 用户更改产品总开关时的回调。
    let setEnabled: (Bool) -> Void

    /// 用户更改“登录时打开”时的回调。
    let setLoginItemRequested: (Bool) -> Void

    /// 用户请求打开 Finder Extension 管理界面时的回调。
    let manageExtension: () -> Void

    /// 用户更改一项命令可见性时的回调。
    let setVisibility: (Bool, ContextCommandFeatureID) -> Void
    let moveCommand: (ContextCommandFeatureID, ContextCommandFeatureID?) -> Void

    /// 用户请求打开完全磁盘访问设置时的回调。
    let openFullDiskAccessSettings: () -> Void

    /// 文件模板操作由主应用或预览边界注入。
    let importTemplate: () async throws -> Void
    let updateTemplateName: (FileTemplateID, FileTemplateNameField, String) async throws -> Void
    let openTemplate: (FileTemplateID) async throws -> Void
    let replaceTemplate: (FileTemplateID) async throws -> Void
    let removeTemplate: (FileTemplateID) async throws -> Void
    let moveTemplate: (FileTemplateID, FileTemplateID?) async throws -> Void
    let reloadTemplates: () async -> Void

    /// 草稿随状态页窗口保留；侧栏切换先完成当前名称提交。
    @StateObject private var templateNameEditing = FileTemplateNameEditingSession()
    @StateObject private var templateActions = FileTemplatePageActions()

    private var paneSelection: Binding<StatusPagePane> {
        Binding(get: { selectedPane }, set: selectPane)
    }

    private func selectPane(_ pane: StatusPagePane) {
        guard pane != selectedPane else { return }
        guard templateNameEditing.draft != nil else {
            selectedPane = pane
            return
        }
        Task {
            guard await templateNameEditing.finishEditing() else { return }
            selectedPane = pane
        }
    }

    /// 构造不含外部读写的双栏设置界面。
    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            detail
                .frame(width: StatusPageStyle.detailWidth, height: StatusPageStyle.pageHeight)
        }
        .frame(height: StatusPageStyle.pageHeight)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            Task { await templateNameEditing.finishEditing() }
        }
    }

    /// 显示产品身份与设置分类的窄侧栏。
    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: StatusPageStyle.rowSpacing) {
                Image("SettingsAppIcon")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(
                        width: StatusPageStyle.appIconFrameSize,
                        height: StatusPageStyle.appIconFrameSize
                    )
                    .accessibilityLabel(displayName)

                Text(verbatim: "V\(version)")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, StatusPageStyle.contentPadding)

            List(StatusPagePane.allCases, selection: paneSelection) { pane in
                HStack(spacing: StatusPageStyle.rowSpacing) {
                    SettingsComponents.monochromeSystemIcon(pane.systemImageName)

                    Text(pane.title)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .tag(pane)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if selectedPane != pane {
                                selectPane(pane)
                            }
                        }
                )
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .frame(width: StatusPageStyle.sidebarWidth, height: StatusPageStyle.pageHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 根据侧栏选择显示对应设置内容。
    @ViewBuilder
    private var detail: some View {
        switch selectedPane {
        case .general:
            GeneralSettingsPage(
                displayName: displayName,
                configuration: configuration,
                systemState: systemState,
                loginItemState: loginItemState,
                setEnabled: setEnabled,
                setLoginItemRequested: setLoginItemRequested,
                manageExtension: manageExtension,
                openFullDiskAccessSettings: openFullDiskAccessSettings
            )
        case .contextMenu:
            CommandMenuSettingsPage(
                descriptors: descriptors,
                configuration: configuration,
                systemState: systemState,
                setVisibility: setVisibility,
                moveCommand: moveCommand
            )
        case .newFileTemplates:
            NewFileTemplateSettingsPage(
                state: fileTemplateState,
                isUpdating: isUpdatingNewFileTemplates,
                nameEditing: templateNameEditing,
                actions: templateActions,
                importTemplate: importTemplate,
                updateName: updateTemplateName,
                openTemplate: openTemplate,
                replaceTemplate: replaceTemplate,
                removeTemplate: removeTemplate,
                moveTemplate: moveTemplate,
                reload: reloadTemplates
            )
        }
    }

}

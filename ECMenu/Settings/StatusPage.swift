/**
 把共享业务控制器、系统状态和模板文件选择操作接入配置界面。
 持有页面选择与系统事实快照，在页面出现及应用激活时刷新外部状态。
 */

import AppKit
import SwiftUI

/// 读取系统与应用状态，并把确定的呈现值交给状态页内容。
struct StatusPage: View {
    /// 主应用注入的菜单配置真相源。
    @EnvironmentObject private var commandMenuConfig: CommandMenuConfigController

    /// 主应用注入的登录项系统状态真相源。
    @EnvironmentObject private var loginItemController: LoginItemController

    /// 主应用注入的模板库呈现状态与操作入口。
    @EnvironmentObject private var newFileTemplates: FileTemplateController

    /// 上一次查看的设置分类；首次打开时进入“通用”。
    @AppStorage("status-page-selected-pane")
    private var selectedPaneRawValue = StatusPagePane.general.rawValue

    let descriptors: [ContextCommandDescriptor]
    let systemServices: StatusPageSystemServices

    /// 系统事实由设置会话持有，所有系统读取由装配层注入。
    @State private var systemState: StatusPageSystemState

    init(descriptors: [ContextCommandDescriptor], systemServices: StatusPageSystemServices) {
        self.descriptors = descriptors
        self.systemServices = systemServices
        _systemState = State(initialValue: systemServices.read(descriptors: descriptors))
    }

    /// 把持久化字符串转换为页面使用的有限分类。
    private var selectedPane: Binding<StatusPagePane> {
        Binding(
            get: {
                StatusPagePane(rawValue: selectedPaneRawValue) ?? .general
            },
            set: { pane in
                selectedPaneRawValue = pane.rawValue
            }
        )
    }

    /// 把产品状态和副作用回调注入纯呈现内容。
    var body: some View {
        StatusPageContent(
            displayName: ApplicationMetadata.displayName,
            version: ApplicationMetadata.version,
            selectedPane: selectedPane,
            systemState: systemState,
            loginItemState: loginItemController.state,
            descriptors: descriptors,
            configuration: commandMenuConfig.configuration,
            fileTemplateState: newFileTemplates.state,
            isUpdatingNewFileTemplates: newFileTemplates.isUpdating,
            setEnabled: { isEnabled in
                commandMenuConfig.setEnabled(isEnabled)
            },
            setLoginItemRequested: { isRequested in
                if !loginItemController.setRequested(isRequested) {
                    NSSound.beep()
                }
            },
            manageExtension: {
                systemServices.manageExtension()
            },
            setVisibility: { isVisible, featureID in
                commandMenuConfig.setVisible(isVisible, for: featureID)
            },
            openFullDiskAccessSettings: {
                if !systemServices.openFullDiskAccessSettings() {
                    NSSound.beep()
                }
            },
            importTemplate: importTemplate,
            updateTemplateName: newFileTemplates.updateName,
            openTemplate: newFileTemplates.openTemplate,
            replaceTemplate: replaceTemplate,
            removeTemplate: newFileTemplates.removeTemplate,
            reloadTemplates: newFileTemplates.reload
        )
        .task {
            await newFileTemplates.loadIfNeeded()
        }
        .onAppear {
            refreshSystemState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshSystemState()
        }
    }

    /// 系统选择器只选择一个普通文件；模板库再验证并保存独立副本。
    private func importTemplate() async throws {
        guard let url = await FileTemplateFileChooser.chooseFile(title: NewFileTemplatesText.add) else { return }
        try await newFileTemplates.importFile(at: url)
    }

    private func replaceTemplate(id: FileTemplateID) async throws {
        guard let url = await FileTemplateFileChooser.chooseFile(title: NewFileTemplatesText.replace) else { return }
        try await newFileTemplates.replaceTemplate(id: id, at: url)
    }

    // MARK: - ==================== 副作用：刷新系统状态 ====================

    /// 在页面出现或应用重新激活时刷新全部外部系统事实。
    private func refreshSystemState() {
        systemState = systemServices.read(
            descriptors: descriptors
        )
        loginItemController.refresh()
    }
}


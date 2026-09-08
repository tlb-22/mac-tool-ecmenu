/**
 构造并持有菜单配置、模板、命令运行时、进度反馈与 IPC 的应用依赖图。
 在进程入口连接生产适配器，并让窗口与后台服务共享同一份业务状态。
 */

import Foundation

/// 显式构造并持有主应用进程的唯一依赖图。
@MainActor
final class ApplicationComposition {
    let commandMenuSettings: CommandMenuSettingsController
    let fileTemplateLibrary: FileTemplateLibrary
    let fileTemplateOperations: FileTemplateOperations
    let newFileTemplates: FileTemplateController
    let loginItemController: LoginItemController
    let progressCenter: ContextCommandProgressCenter
    let router: ContextCommandRouter
    let applicationIPCServer: ApplicationIPCServer
    let statusPageWindowController: StatusPageWindowController
    private let progressPresenter: ContextCommandProgressPresenter
    private let imageSettingsPrompt: ImageCompressionSettingsPrompt

    init(didCloseConfiguration: @escaping () -> Void) {
        let publisher = MenuChangePublisher(notify: CommandMenuSettingsChannel.signalConfigurationChange)
        let commandMenuSettings = CommandMenuSettingsController(
            store: CommandMenuSettingsStore(defaults: .standard), publisher: publisher
        )
        let library = FileTemplateLibrary()
        let templateOperations = FileTemplateOperations(
            library: library, openFile: FileTemplateOpener.open,
            didChange: { _ in publisher.signal() }
        )
        let newFileTemplates = FileTemplateController(operations: templateOperations)
        let loginItemController = LoginItemController(service: .mainApplication)
        let progressPresenter = ContextCommandProgressPresenter()
        let progressCenter = ContextCommandProgressCenter(render: progressPresenter.render)
        let prompt = ImageCompressionSettingsPrompt(present: { $0.present() })
        let imageSettings = ImageCompressionSettingsCoordinator(
            store: ImageCompressionSettingsStore(defaults: .standard),
            request: { initial, onConfirm in
                await prompt.request(settings: initial, onConfirm: onConfirm)
            }
        )
        let handlers = ContextCommandComposition.makeHandlers(dependencies: ContextCommandDependencies(
            readTemplate: { try await templateOperations.content(for: $0) },
            requestImageSettings: { await imageSettings.requestSettings() }
        ))
        let router = ContextCommandRouter(handlers: handlers, progressCenter: progressCenter)
        let snapshots = MenuSnapshotProvider(
            configuration: { commandMenuSettings.configuration },
            templates: { try await templateOperations.load() }
        )

        self.commandMenuSettings = commandMenuSettings
        fileTemplateLibrary = library
        fileTemplateOperations = templateOperations
        self.newFileTemplates = newFileTemplates
        self.loginItemController = loginItemController
        self.progressPresenter = progressPresenter
        self.progressCenter = progressCenter
        imageSettingsPrompt = prompt
        self.router = router
        applicationIPCServer = ApplicationIPCServer(
            router: router, menuSnapshot: { await snapshots.currentSnapshot() }, didStart: publisher.signal
        )
        statusPageWindowController = StatusPageWindowController(
            commandMenuSettings: commandMenuSettings,
            loginItemController: loginItemController,
            newFileTemplates: newFileTemplates,
            descriptors: handlers.descriptors,
            systemServices: .live,
            didClose: didCloseConfiguration
        )
    }
}

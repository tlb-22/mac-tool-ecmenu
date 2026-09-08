/**
 将各业务命令的描述、执行处理器与反馈适配器装配为运行时注册表。
 从同一组注册声明生成界面命令目录和执行处理器，并注入平台及反馈依赖。
 */

import Foundation

/// 每个进程实例提供的能力入口；注册声明本身只保存不可变工厂。
@MainActor
struct ContextCommandDependencies {
    let readTemplate: @Sendable (FileTemplateID) async throws -> FileTemplateContent
    let requestImageSettings: @MainActor @Sendable () async -> ImageCompressionSettings?
}

@MainActor
private struct ContextCommandRegistration {
    let descriptor: ContextCommandDescriptor
    let makeHandler: (ContextCommandDependencies) -> AnyContextCommandHandler

    init<Handler: ContextCommandHandling>(make: @escaping (ContextCommandDependencies) -> Handler) {
        descriptor = Handler.Command.descriptor
        makeHandler = { AnyContextCommandHandler(make($0)) }
    }
}

/// 产品注册顺序同时提供界面目录与执行端工厂；不持有库、窗口或运行中的任务。
@MainActor
enum ContextCommandComposition {
    private static let registrations: [ContextCommandRegistration] = [
        ContextCommandRegistration { dependencies in
            CreateNewFileHandler(readTemplate: dependencies.readTemplate, writer: .system, present: CreateNewFileFeedback.present)
        },
        ContextCommandRegistration { _ in CopyPathHandler(platform: .system, present: CopyPathFeedback.present) },
        ContextCommandRegistration { _ in HideItemsHandler(platform: .system, present: VisibilityFeedback.present) },
        ContextCommandRegistration { _ in ShowItemsHandler(platform: .system, present: VisibilityFeedback.present) },
        ContextCommandRegistration { dependencies in
            CompressImagesHandler(requestSettings: dependencies.requestImageSettings, platform: .system, now: { Date() }, present: ImageCompressionFeedback.present)
        },
        ContextCommandRegistration { _ in OpenInVSCodeHandler(platform: .system, present: OpenInApplicationFeedback.present) },
        ContextCommandRegistration { _ in OpenInITerm2Handler(platform: .system, present: OpenInApplicationFeedback.present) },
    ]

    static var descriptors: [ContextCommandDescriptor] { registrations.map(\.descriptor) }

    static func makeHandlers(dependencies: ContextCommandDependencies) -> ContextCommandHandlers {
        ContextCommandHandlers(registeredHandlers: registrations.map { $0.makeHandler(dependencies) })
    }
}

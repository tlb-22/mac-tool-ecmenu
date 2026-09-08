/**
 将不同命令类型的叶子统一纳入菜单运行时，并在构建期间固定可直接投递的命令参数。
 准备结果保留呈现描述和调用闭包，点击时沿既定客户端发送同一条类型化命令。
 */

import Foundation
import OSLog

/// 菜单构建时已经冻结参数、可以直接调用的 Action。
final class PreparedContextMenuAction {
    /// Finder 渲染叶子所需的产品信息。
    let descriptor: FinderContextMenuActionDescriptor

    /// 已经捕获类型化 Command 的单次投递行为。
    private let performClosure: () -> Void

    /// 绑定展示信息和准备好的调用。
    init(
        descriptor: FinderContextMenuActionDescriptor,
        perform: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        performClosure = perform
    }

    /// 投递菜单构建时已经准备好的命令。
    func perform() {
        performClosure()
    }
}

/// 隐藏具体 Command 类型，供产品菜单树统一存储叶子。
final class AnyContextMenuAction {
    /// 菜单 Action 日志共用的稳定分类。
    private static let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "ContextCommandFeature"
    )

    /// 具体叶子的完整身份和展示信息。
    let descriptor: FinderContextMenuActionDescriptor

    /// 类型擦除后的命令准备行为。
    private let prepareClosure: (
        FinderContextMenuEvaluationContext
    ) -> PreparedContextMenuAction?

    /// 为一个 Feature 的具体叶子绑定共享命令类型和投递客户端。
    init<Command: ContextCommandPayload>(
        _ action: ContextMenuAction<Command>,
        featureID: ContextCommandFeatureID,
        commandClient: ContextCommandClient
    ) {
        let descriptor = FinderContextMenuActionDescriptor(
            id: FinderContextMenuActionID(
                featureID: featureID,
                localID: action.id
            ),
            title: action.title,
            icon: action.icon,
            requiredApplication: Command.descriptor.requiredApplication
        )
        self.descriptor = descriptor
        prepareClosure = { context in
            guard let command = action.command(context) else {
                return nil
            }
            return PreparedContextMenuAction(descriptor: descriptor) {
                let actionName = "\(featureID.rawValue)/\(action.id.rawValue)"
                Self.logger.debug(
                    "Handling Finder action \(actionName, privacy: .public)"
                )
                commandClient.send(command)
            }
        }
    }

    /// 在菜单构建时同时决定可见性并冻结命令。
    func prepare(
        in context: FinderContextMenuEvaluationContext
    ) -> PreparedContextMenuAction? {
        prepareClosure(context)
    }
}

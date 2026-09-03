import Foundation

/// 集中保存进度窗口预览中需要反复手动调整的场景参数。
@MainActor
private enum ContextCommandProgressPreviewParameters {
    /// 同时呈现的压缩图片任务数量；改为 `3` 可检查多任务布局。
    static let taskCount = 1

    /// 每项模拟压缩任务需要处理的图片总数。
    static let totalUnitCount = 836

    /// 打开预览时每项任务已经处理的图片数。
    static let completedUnitCount = 94

    /// 预览无需等待生产环境的短任务隐藏阈值。
    static let displayDelay: Duration = .zero
}

/// 使用共享生产渲染器检查一个或多个并发任务的进度窗口。
@MainActor
enum ContextCommandProgressPreview: ApplicationPreview {
    /// `preview-ui.sh` 使用的稳定预览标识。
    static let id = "context-command-progress"

    /// 注入静态内存状态，不触碰文件系统或真实命令 Router。
    static func present() -> AnyObject {
        ContextCommandProgressPreviewSession()
    }
}

/// 保活独立进度中心和全部模拟 reporter，不复制任务窗口视图代码。
@MainActor
private final class ContextCommandProgressPreviewSession {
    /// 预览专用中心；不会加入真实 Router 的共享任务集合。
    private let center: ContextCommandProgressCenter

    /// 每个独立 request ID 对应一个同时存在的模拟压缩任务。
    private let reporters: [ContextCommandProgressReporter]

    /// 按集中参数构造 N 个已经推进到指定位置的并发任务。
    init() {
        let parameters = ContextCommandProgressPreviewParameters.self
        precondition(parameters.taskCount > 0)
        precondition(parameters.totalUnitCount > 0)
        precondition(
            (0...parameters.totalUnitCount).contains(
                parameters.completedUnitCount
            )
        )

        let center = ContextCommandProgressCenter(
            displayDelay: parameters.displayDelay
        )
        self.center = center
        reporters = (0..<parameters.taskCount).map { _ in
            ContextCommandProgressReporter(
                center: center,
                requestID: UUID(),
                descriptor: CompressImagesCommand.descriptor
            )
        }

        for reporter in reporters {
            reporter.begin(
                totalUnitCount: parameters.totalUnitCount
            )
            for _ in 0..<parameters.completedUnitCount {
                reporter.advance()
            }
        }
    }
}

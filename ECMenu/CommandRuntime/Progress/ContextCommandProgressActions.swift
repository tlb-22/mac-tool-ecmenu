/**
 定义进度界面可触发的取消和关闭操作。
 将展示层回调绑定到进度状态所有者，避免界面直接修改任务状态。
 */

import Foundation

/// 呈现层可发回进度所有者的用户意图；不直接取消业务 Task。
@MainActor
struct ContextCommandProgressActions {
    let cancel: (UUID) -> Void
    let dismiss: () -> Void
}

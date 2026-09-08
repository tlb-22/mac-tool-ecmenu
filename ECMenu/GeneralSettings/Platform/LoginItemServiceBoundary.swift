/**
 把 Service Management 的登录项状态和注册操作转换为应用可注入的系统边界。
 保留需要用户批准等实际系统状态，供控制器决定交互。
 */

import ServiceManagement

/// 主应用登录项在产品设置中需要表达的有限状态。
enum LoginItemRegistrationState: Equatable, Sendable {
    /// 用户没有要求主应用在登录时启动。
    case notRegistered

    /// 登录项已经登记并获得系统批准。
    case enabled

    /// 登录项已经登记，但需要用户在系统设置中批准。
    case requiresApproval

    /// 本次状态查询无法定位主应用登录项；仍可由用户发起登记。
    case notFound

    /// 开关是否应表达用户已经请求登记登录项。
    var isRequested: Bool {
        switch self {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound:
            false
        }
    }

    /// 把 Service Management 的平台状态收敛为产品状态。
    /// - Parameter status: `SMAppService.mainApp` 当前报告的状态。
    init(status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .notRegistered
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        @unknown default:
            self = .notFound
        }
    }
}

/// 隔离 Service Management 读写，允许测试使用内存边界。
@MainActor
struct LoginItemServiceBoundary {
    /// 读取系统当前登记和批准状态。
    let status: () -> SMAppService.Status

    /// 请求系统登记主应用登录项。
    let register: () throws -> Void

    /// 请求系统取消主应用登录项登记。
    let unregister: () throws -> Void

    /// 生产环境使用的主应用登录项边界。
    static let mainApplication = LoginItemServiceBoundary(
        status: { SMAppService.mainApp.status },
        register: { try SMAppService.mainApp.register() },
        unregister: { try SMAppService.mainApp.unregister() }
    )
}


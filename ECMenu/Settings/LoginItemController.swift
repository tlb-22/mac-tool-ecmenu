import Combine
import Foundation
import OSLog
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

    /// 尚需用户处理时显示的状态文字；其他状态保持界面简洁。
    var pendingApprovalTitle: String? {
        switch self {
        case .requiresApproval:
            "未批准"
        case .notRegistered, .enabled, .notFound:
            nil
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

/// 持有登录项系统状态，并执行用户发起的登记变更。
@MainActor
final class LoginItemController: ObservableObject {
    /// 状态页观察的当前登记和批准结果。
    @Published private(set) var state: LoginItemRegistrationState

    /// 可替换的 Service Management 副作用边界。
    private let service: LoginItemServiceBoundary

    /// 记录无法恢复的系统登录项错误。
    private let logger = Logger(
        subsystem: ApplicationLogging.subsystem,
        category: "LoginItem"
    )

    /// 从生产环境的主应用登录项边界读取初始状态。
    convenience init() {
        self.init(service: .mainApplication)
    }

    /// 从可替换边界读取初始状态。
    /// - Parameter service: 测试提供的登录项服务。
    init(service: LoginItemServiceBoundary) {
        self.service = service
        state = LoginItemRegistrationState(status: service.status())
    }

    /// 重新读取系统设置中的登记和批准状态。
    func refresh() {
        state = LoginItemRegistrationState(status: service.status())
    }

    /// 根据用户开关登记或取消登记主应用登录项。
    /// - Parameter isRequested: 用户是否要求主应用在登录时启动。
    /// - Returns: 系统操作成功，或系统已处于等价目标状态时为 `true`。
    @discardableResult
    func setRequested(_ isRequested: Bool) -> Bool {
        refresh()
        guard state.isRequested != isRequested else {
            return true
        }
        do {
            if isRequested {
                try service.register()
            } else {
                try service.unregister()
            }
            refresh()
            return true
        } catch {
            refresh()

            // Service Management can report denial while still preserving a
            // registered item that the user may later approve in Settings.
            if state.isRequested == isRequested {
                logger.info(
                    "Login item reached the requested registration state after Service Management reported an error"
                )
                return true
            }

            logger.error(
                "Could not update the main application login item: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }
}

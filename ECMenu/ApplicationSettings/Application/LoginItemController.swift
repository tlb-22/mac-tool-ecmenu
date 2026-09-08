/**
 协调登录启动选项的读取、注册、注销与界面状态刷新。
 以系统服务返回的事实为状态来源，并向设置页发布操作结果。
 */

import Combine
import Foundation
import OSLog

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

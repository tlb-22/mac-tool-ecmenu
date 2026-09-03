import ServiceManagement
import XCTest
@testable import ECMenu

/// 验证系统登录项状态映射与登记副作用边界。
@MainActor
final class LoginItemControllerTests: XCTestCase {
    /// 未登记状态是默认关闭且不显示批准结果。
    func testNotRegisteredStateIsOffWithoutApprovalLabel() {
        let state = LoginItemRegistrationState(
            status: .notRegistered
        )

        XCTAssertEqual(state, .notRegistered)
        XCTAssertFalse(state.isRequested)
        XCTAssertNil(state.pendingApprovalTitle)
    }

    /// 两种登记状态都保持开关开启，只有等待批准时显示提示。
    func testRegisteredStatesOnlyDescribePendingApproval() {
        let enabled = LoginItemRegistrationState(status: .enabled)
        let requiresApproval = LoginItemRegistrationState(
            status: .requiresApproval
        )

        XCTAssertTrue(enabled.isRequested)
        XCTAssertNil(enabled.pendingApprovalTitle)
        XCTAssertTrue(requiresApproval.isRequested)
        XCTAssertEqual(
            requiresApproval.pendingApprovalTitle?.key,
            "statusPage.general.loginItem.notApproved"
        )
    }

    /// 状态查询找不到主应用登录项时仍显示关闭，不伪装为已登记。
    func testNotFoundStateIsOffWithoutApprovalLabel() {
        let state = LoginItemRegistrationState(status: .notFound)

        XCTAssertEqual(state, .notFound)
        XCTAssertFalse(state.isRequested)
        XCTAssertNil(state.pendingApprovalTitle)
    }

    /// 状态查询未找到服务时仍应允许用户发起真实登记。
    func testControllerCanRegisterAfterNotFoundStatus() {
        let service = LoginItemServiceSpy(status: .notFound)
        let controller = LoginItemController(service: service.boundary)

        XCTAssertTrue(controller.setRequested(true))
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.state, .enabled)
    }

    /// 登记后需要批准仍是成功的开启请求，并可以再次取消登记。
    func testControllerRegistersRequiresApprovalAndUnregisters() {
        let service = LoginItemServiceSpy(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let controller = LoginItemController(service: service.boundary)

        XCTAssertTrue(controller.setRequested(true))
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.state, .requiresApproval)

        XCTAssertTrue(controller.setRequested(false))
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(controller.state, .notRegistered)
    }

    /// 系统拒绝登记调用但保留待批准登记时，开启请求仍然成立。
    func testControllerAcceptsRegisterErrorThatLeavesPendingApproval() {
        let service = LoginItemServiceSpy(status: .notRegistered)
        service.statusAfterRegisterError = .requiresApproval
        service.registerError = LoginItemTestFailure.expected
        let controller = LoginItemController(service: service.boundary)

        XCTAssertTrue(controller.setRequested(true))
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.state, .requiresApproval)
    }

    /// 重复设置同一状态不应重复调用 Service Management。
    func testControllerDoesNotRepeatEquivalentOperation() {
        let service = LoginItemServiceSpy(status: .enabled)
        let controller = LoginItemController(service: service.boundary)

        XCTAssertTrue(controller.setRequested(true))
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    /// 系统操作失败且状态没有改变时，控制器应报告失败。
    func testControllerReportsUnrecoveredServiceFailure() {
        let service = LoginItemServiceSpy(status: .notRegistered)
        service.registerError = LoginItemTestFailure.expected
        let controller = LoginItemController(service: service.boundary)

        XCTAssertFalse(controller.setRequested(true))
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(controller.state, .notRegistered)
    }

    /// 取消登记失败时，开关必须继续表达系统仍然登记的事实。
    func testControllerReportsUnregisterFailureWithoutChangingState() {
        let service = LoginItemServiceSpy(status: .enabled)
        service.unregisterError = LoginItemTestFailure.expected
        let controller = LoginItemController(service: service.boundary)

        XCTAssertFalse(controller.setRequested(false))
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(controller.state, .enabled)
    }
}

/// 使用内存状态模拟 `SMAppService.mainApp` 的测试边界。
@MainActor
private final class LoginItemServiceSpy {
    /// 当前由读取边界返回的平台状态。
    var status: SMAppService.Status

    /// 登记成功后切换到的平台状态。
    var statusAfterRegister = SMAppService.Status.enabled

    /// 登记边界需要抛出的模拟错误。
    var registerError: Error?

    /// 登记抛错前需要保留的平台状态。
    var statusAfterRegisterError: SMAppService.Status?

    /// 取消登记边界需要抛出的模拟错误。
    var unregisterError: Error?

    /// 已执行的登记调用次数。
    private(set) var registerCallCount = 0

    /// 已执行的取消登记调用次数。
    private(set) var unregisterCallCount = 0

    /// 创建一个指定初始平台状态的内存服务。
    init(status: SMAppService.Status) {
        self.status = status
    }

    /// 构造供产品控制器注入的闭包边界。
    var boundary: LoginItemServiceBoundary {
        LoginItemServiceBoundary(
            status: { [self] in status },
            register: { [self] in
                registerCallCount += 1
                if let registerError {
                    if let statusAfterRegisterError {
                        status = statusAfterRegisterError
                    }
                    throw registerError
                }
                status = statusAfterRegister
            },
            unregister: { [self] in
                unregisterCallCount += 1
                if let unregisterError {
                    throw unregisterError
                }
                status = .notRegistered
            }
        )
    }
}

/// 测试 Service Management 无法完成请求时使用的确定错误。
private enum LoginItemTestFailure: Error {
    case expected
}

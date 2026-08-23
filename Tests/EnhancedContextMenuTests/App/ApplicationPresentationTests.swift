import AppKit
import CoreServices
import XCTest
@testable import EnhancedContextMenu

/// 验证配置窗口生命周期不会等同于常驻命令宿主生命周期。
final class ApplicationPresentationTests: XCTestCase {
    /// 登录项枚举只有位于 Property Data 参数中时才表达登录启动。
    func testInitialOpenSourceUsesPropertyDataLoginItemEnumeration() {
        let userEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        let loginItemEvent = userEvent.copy() as! NSAppleEventDescriptor
        loginItemEvent.setParam(
            NSAppleEventDescriptor(
                enumCode: keyAELaunchedAsLogInItem
            ),
            forKeyword: keyAEPropData
        )

        XCTAssertEqual(
            ApplicationInitialOpenSource(
                openApplicationEvent: userEvent
            ),
            .user
        )
        XCTAssertEqual(
            ApplicationInitialOpenSource(
                openApplicationEvent: loginItemEvent
            ),
            .loginItem
        )
    }

    /// Property Data 中的其他启动枚举不能被误判为登录项启动。
    func testInitialOpenSourceRejectsOtherPropertyDataEnumeration() {
        let serviceItemEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        serviceItemEvent.setParam(
            NSAppleEventDescriptor(
                enumCode: keyAELaunchedAsServiceItem
            ),
            forKeyword: keyAEPropData
        )

        XCTAssertEqual(
            ApplicationInitialOpenSource(
                openApplicationEvent: serviceItemEvent
            ),
            .user
        )
    }

    /// 登录项启动必须保持后台状态，即使此前状态值为可见。
    func testLoginItemLaunchProducesHiddenState() {
        XCTAssertEqual(
            ApplicationPresentationMode.configurationHidden.transition(
                for: .launchAtLogin
            ),
            .configurationHidden
        )
        XCTAssertEqual(
            ApplicationPresentationMode.configurationVisible.transition(
                for: .launchAtLogin
            ),
            .configurationHidden
        )
    }

    /// 普通打开与重复打开都应确定地进入配置可见状态。
    func testShowConfigurationProducesVisibleState() {
        XCTAssertEqual(
            ApplicationPresentationMode.configurationHidden.transition(
                for: .showConfiguration
            ),
            .configurationVisible
        )
        XCTAssertEqual(
            ApplicationPresentationMode.configurationVisible.transition(
                for: .showConfiguration
            ),
            .configurationVisible
        )
    }

    /// 隐藏配置事件应确定地进入后台状态。
    func testHideConfigurationProducesHiddenState() {
        XCTAssertEqual(
            ApplicationPresentationMode.configurationVisible.transition(
                for: .hideConfiguration
            ),
            .configurationHidden
        )
        XCTAssertEqual(
            ApplicationPresentationMode.configurationHidden.transition(
                for: .hideConfiguration
            ),
            .configurationHidden
        )
    }

    /// 关闭唯一 Status Page 应退出配置形态，重复关闭保持幂等。
    func testConfigurationWindowCloseProducesHiddenState() {
        XCTAssertEqual(
            ApplicationPresentationMode.configurationVisible.transition(
                for: .configurationWindowDidClose
            ),
            .configurationHidden
        )
        XCTAssertEqual(
            ApplicationPresentationMode.configurationHidden.transition(
                for: .configurationWindowDidClose
            ),
            .configurationHidden
        )
    }
}

import AppKit
import CoreServices
import XCTest
@testable import EnhancedContextMenu

/// 验证首次打开事件只根据系统 Property Data 判定启动来源。
final class ApplicationInitialOpenSourceTests: XCTestCase {
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
}

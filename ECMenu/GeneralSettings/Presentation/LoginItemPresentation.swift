/**
 为需要用户批准的登录项状态提供本地化界面提示。
 将注册状态对应的显示文案集中在表现层。
 */

import Foundation

extension LoginItemRegistrationState {
    /// 尚需用户处理时显示的状态文字；其他状态保持界面简洁。
    var pendingApprovalTitle: LocalizedStringResource? {
        switch self {
        case .requiresApproval:
            LocalizedStringResource(
                "statusPage.general.loginItem.notApproved",
                defaultValue: "Not Approved",
                comment: "Status shown when the login item awaits system approval"
            )
        case .notRegistered, .enabled, .notFound:
            nil
        }
    }

}

import Foundation

/// 为当前可执行 Bundle 提供统一且不可缺失的日志身份。
nonisolated enum ApplicationLogging {
    /// 使用构建产物声明的 Bundle ID 对统一日志分组。
    static let subsystem: String = {
        guard
            let bundleIdentifier = Bundle.main.bundleIdentifier,
            !bundleIdentifier.isEmpty
        else {
            preconditionFailure(
                "The main executable bundle has no bundle identifier"
            )
        }
        return bundleIdentifier
    }()
}

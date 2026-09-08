/**
 为共享源码提供当前可执行 Bundle 的统一日志 subsystem，使各产品日志按自身身份归组。
 身份由构建产物声明提供并在进程内复用，缺失时明确暴露构建不变量错误。
 */

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

import Darwin
import Foundation

// MARK: - ==================== 系统错误快照 ====================

/// 在系统边界冻结任意底层错误中可安全跨并发域传递的诊断字段。
nonisolated struct SystemErrorSnapshot: Equatable, Sendable {
    /// Foundation、POSIX、Launch Services 或功能适配器的错误域。
    let domain: String

    /// 错误域中的原始错误码。
    let code: Int

    /// 系统或适配器提供的本地化错误说明。
    let localizedDescription: String

    /// 立即捕获底层错误，避免任意 `Error` 逃出副作用边界。
    /// - Parameter error: 系统 API 返回的原始错误。
    init(capturing error: Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
        localizedDescription = error.localizedDescription
    }
}

// MARK: - ==================== 文件系统错误分类 ====================

/// 文件系统错误中可以跨功能共享的底层原因，不决定具体用户反馈。
nonisolated enum FileSystemErrorKind: Equatable, Sendable {
    /// 当前进程缺少读取或写入目标所需的权限。
    case permissionDenied

    /// 目标所在的文件系统只允许读取。
    case readOnlyFileSystem

    /// 路径不存在，或路径中的某一级已经不再是目录。
    case unavailable

    /// 不属于上述稳定类别的底层失败。
    case other

    /// 把 Cocoa 与 POSIX 文件系统错误码映射为稳定原因。
    /// - Parameter systemError: 文件系统调用边界捕获的错误快照。
    init(classifying systemError: SystemErrorSnapshot) {
        if systemError.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: systemError.code) {
            case .fileReadNoPermission, .fileWriteNoPermission:
                self = .permissionDenied
            case .fileWriteVolumeReadOnly:
                self = .readOnlyFileSystem
            case .fileNoSuchFile, .fileReadNoSuchFile:
                self = .unavailable
            default:
                self = .other
            }
            return
        }

        if systemError.domain == NSPOSIXErrorDomain {
            switch systemError.code {
            case Int(EACCES), Int(EPERM):
                self = .permissionDenied
            case Int(EROFS):
                self = .readOnlyFileSystem
            case Int(ENOENT), Int(ENOTDIR):
                self = .unavailable
            default:
                self = .other
            }
            return
        }

        self = .other
    }
}

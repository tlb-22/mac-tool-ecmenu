# 文件访问边界

证据分类与验证环境见[平台边界](Main.md)。本文件记录产品文件操作实际受到的授权约束；Finder Extension 的管理范围见 [Finder 管理位置](Finder/ManagedLocations.md)。

## 进程权限分工

主应用关闭 App Sandbox，Finder Extension 保持 App Sandbox。Extension 只读取菜单判定和构造命令所需的瞬时事实，真正的文件操作由主应用执行。动作链路不弹出逐目录 `NSOpenPanel`，也不保存 security-scoped bookmark。

菜单阶段观察到的存在性、目录类型和其他文件事实不是跨进程的永久保证。主应用执行时仍按具体功能需要读取当前系统事实，并处理此时真实可能发生的访问失败。

## 授权边界

“完全磁盘访问”只放宽 TCC 保护，不授予 root 权限，也不能绕过 POSIX 权限、ACL、只读文件系统、SIP 或 Data Vault。Finder Sync 的 `directoryURLs` 只定义 Extension 管理范围，同样不增加主应用权限。

Xcode 26.6 附带的 macOS 26.5 SDK 没有为普通应用提供通用的“完全磁盘访问”状态查询。读取某个受保护路径成功或失败，只能说明该次访问结果，不能确定失败来自哪一种授权机制。因此状态页只提供中性的系统设置入口，不推断或保存二值授权状态；具体命令按实际文件操作结果分类反馈。

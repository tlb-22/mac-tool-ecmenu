# 文件系统范围

以下位置属于产品的核心验收范围：

- 本机启动磁盘上的 Finder 目录，包括用户目录和 `/Applications`。
- Finder 中可见的非隐藏挂载卷，包括挂载在 `/Volumes` 下的外置磁盘及其任意深度子目录。

应用运行期间新挂载、卸载或重命名卷后，Finder 菜单范围应自动更新，不要求用户重启应用或 Finder。

文件操作不得在点击动作后弹出逐文件夹授权面板。Finder Extension 启用和“完全磁盘访问”由[状态页](StatusPage.md#通用)提供一次性系统设置入口；实际操作仍遵守文件系统写权限、只读卷和 macOS 系统完整性保护。

对应技术边界见[Finder 管理位置](../Technical/Platform/Finder/ManagedLocations.md)和[文件访问](../Technical/Platform/FileAccess.md)。

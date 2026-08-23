# 菜单可见性配置

产品允许用户整体停用 Finder 菜单，也允许隐藏固定功能，但功能集合、名称、顺序和行为仍由程序定义。菜单行为见[需求总述](../Requirements/Main.md)；Feature 与 Action 的身份边界见[进程、交付与权限边界](ExecutionArchitecture.md)。

## 状态模型

配置保存默认开启的产品总开关，以及偏离默认值的“隐藏 Feature ID”集合：

- 总开关关闭时，Finder 不构建任何产品菜单，但不改写各 Feature 的可见性。
- 旧格式没有总开关时迁移为开启，保持升级前行为。
- 新增功能不在集合中，升级后默认可见，不需要迁移每个布尔字段。
- 重新显示功能就是删除对应 ID，不产生冗余的显式 `true`。
- 未知 ID 保留，使较新版本的配置经过较旧版本读写后仍可恢复。
- 一个 Feature 的开关隐藏其贡献的完整 Action 子树，不提供叶子级配置。

当前格式兼容把既有可见性字典迁移为稀疏隐藏 ID 集合。Feature ID 一旦发布即属于持久化契约，不能只因源码重命名而改变。

## 真相源与本地副本

主应用是配置的架构所有者。Finder 必须在主应用尚未运行时也能同步构建右键菜单，因此 Extension 在自己的 `UserDefaults` 中持久化最后一次结构和 schema 有效的配置副本，并在启动后主动请求最新值。主应用不可用或身份验证失败时继续使用最后有效副本；副本只用于可见性，不反向成为新的配置所有者。Debug 与 Release 使用不同 bundle identifier，因此各自的主应用配置和 Extension 副本天然分离，不在两套构建之间自动迁移。

每个构建配置通过 build setting 向两个产品 target 注入同一个 Team-ID 风格 App Group：Release 使用 `GVPW27HJZ5.ecmenu`，Debug 使用 `GVPW27HJZ5.ecmenu.debug`。完整配置通过对应组容器内的 Unix-domain socket 请求和响应。Extension 在发送请求前验证主应用具有同一签名 Team 和当前配置注入的精确 signing identifier；主应用也对称验证 Extension 后才返回配置。两套身份、App Group 与通知 namespace 的完整隔离边界见[进程、交付与权限边界](ExecutionArchitecture.md#构建身份与配置隔离)。

主应用保存配置后只发送不携带正文的分布式变更信号；Extension 收到信号后重新走已验证 socket 拉取。伪造信号最多造成一次无状态拉取尝试，不能把伪造配置写入副本。App Group 只承载 socket，不把主应用与 Extension 的偏好存储合并；稀疏隐藏集合、主应用所有权和 Feature 级开关语义保持不变。

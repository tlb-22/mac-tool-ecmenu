# 菜单配置

产品行为见[状态页](../../Requirements/StatusPage.md)与[Finder 菜单](../../Requirements/FinderMenu.md)。Feature 与 Action 的身份关系见[命令执行](CommandExecution.md)。

## 状态模型

配置只保存默认开启的产品总开关，以及偏离默认值的隐藏 Feature ID 集合：

- 总开关关闭时 Finder 不构建产品菜单，但不改写各 Feature 的可见性。
- Feature 开关隐藏该 Feature 贡献的完整 Action 子树，不产生叶子级配置。
- 新 Feature 不在隐藏集合中，加入产品后默认可见；重新显示 Feature 就是删除对应 ID。

当前解码器只接受字段完整的当前 schema。未来持久化格式升级由独立迁移完成，不在领域解码器中保留旧格式分支。Feature ID 一旦发布就是持久化契约，不因源码重命名而改变。

## 真相源与副本

主应用是配置唯一所有者。Finder Extension 必须在主应用未运行时也能同步构建菜单，因此只在自己的 `UserDefaults` 中保存最后一份结构和 schema 有效的配置副本。副本只供菜单可见性读取，不反向成为配置真相源。

没有有效副本时 Extension 从标准全开启配置开始。Extension 启动时以及收到无正文变更信号后，通过已认证的独立 socket 连接拉取完整配置。主应用不可用、身份验证失败或响应无效时继续使用最后有效副本，不写入半有效状态。

同一时刻最多存在一个配置拉取。拉取期间再次收到变更信号时，当前响应可能已经过时，因此不应用它；连接结束后再拉取一次最终状态。这一规则防止响应乱序覆盖较新配置。

主应用保存配置后发送不携带正文的分布式通知。IPC Server 成功开始监听时也发送一次相同信号，使启动得更早、初次拉取已经失败的 Extension 重新查询；这是配置状态的启动收敛，不会重试任何命令。通知本身不具备修改配置的权限，安全边界见 [IPC](IPC.md#配置变更信号)。App Group 只承载 socket，不合并双方的偏好存储。Debug 与 Release 使用彼此隔离的偏好、通知名和 App Group，具体数值只由[构建身份](../Delivery/BuildIdentity.md)维护。

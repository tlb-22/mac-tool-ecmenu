# 菜单配置

产品行为见[状态页](../../Requirements/StatusPage.md)与[Finder 菜单](../../Requirements/FinderMenu.md)。Feature 与 Action 的身份关系见[命令执行](CommandExecution.md)。

## 状态模型

主应用的菜单开关配置保存在自身 `UserDefaults` 的 `menu-configuration-v1` 键中，内容仍为包含当前 schema 的 JSON 数据，只保存默认开启的产品总开关，以及偏离默认值的隐藏 Feature ID 集合：

- 总开关关闭时 Finder 不构建产品菜单，但不改写各 Feature 的可见性。
- Feature 开关隐藏该 Feature 贡献的完整 Action 子树，不产生叶子级配置。
- 新 Feature 不在隐藏集合中，加入产品后默认可见；重新显示 Feature 就是删除对应 ID。

当前解码器只接受字段完整的当前 schema。未来持久化格式升级由独立迁移完成，不在领域解码器中保留旧格式分支。Feature ID 一旦发布就是持久化契约，不因源码重命名而改变；“新建文件”保留已发布的 `new-text-file` 身份，因此沿用用户原有的显示开关。

主应用发布的完整菜单快照将这份配置与模板菜单状态一起封装，并使用独立的 schema。模板菜单状态区分可用与不可用：可用状态携带有序模板描述，允许清单为空；不可用状态表达主应用尚不能提供模板库。两种状态在存储与 IPC 中保持区别，Finder 在可用空清单或不可用状态下均隐藏整个“新建文件”父菜单。

每个模板描述只包含 `id` 与 `displayName`，不包含内部文件路径、文件内容或默认文件名。创建命令携带模板 ID，主应用从[模板库](../Features/NewFile.md#模板库持久化)取得执行时的名称和内容。

## 真相源与副本

主应用是开关配置和模板库的唯一所有者。Finder Extension 必须在主应用未运行时也能同步构建菜单，因此在自己的 `UserDefaults` 中使用 `menu-configuration-snapshot-v1` 保存最后一份结构和 schema 有效的完整菜单快照。副本只用于菜单构建，不反向成为配置或模板库的真相源。

Extension 的独立缓存迁移只在新快照键不存在时读取旧 `menu-configuration-v1` 副本，保留其中的全部开关值，写入模板菜单不可用的新快照后删除旧键。主应用的同名偏好键属于另一个存储域，不参与这次迁移。

没有有效副本时 Extension 从标准全开启配置和模板菜单不可用状态开始，模板菜单等待主应用发布可用描述后出现。Extension 启动时以及收到无正文变更信号后，通过已认证的独立 socket 连接拉取完整快照。

模板库读取失败时，主应用仍返回当前开关配置与模板菜单不可用状态；这是可以整体应用和缓存的有效快照。Finder 隐藏依赖模板库的“新建文件”菜单，同时继续同步总开关与其他命令的配置，设置页独立呈现模板库错误。连接不可用、身份验证失败、传输失败或响应无效时，Extension 才保留最后有效的完整副本。

同一时刻最多存在一个配置拉取。拉取期间再次收到变更信号时，当前响应可能已经过时，因此不应用它；连接结束后再次读取主应用状态。这一规则防止响应乱序覆盖较新配置。

主应用保存配置或提交模板变更后发送不携带正文的分布式通知。IPC Server 成功开始监听时也发送一次相同信号，使启动得更早、初次拉取已经失败的 Extension 重新查询；这是菜单状态的启动收敛，不会重试任何命令。通知本身不具备修改配置的权限，安全边界见 [IPC](IPC.md#配置变更信号)。App Group 只承载 socket，不合并双方的偏好存储。Debug 与 Release 使用彼此隔离的偏好、模板库、通知名和 App Group，具体身份值只由[构建身份](../Delivery/BuildIdentity.md)维护。

## 通知与持久化的完成边界

Apple 的 [DistributedNotificationCenter 契约](https://developer.apple.com/documentation/foundation/distributednotificationcenter)允许通知延迟或丢失，不提供有限到达时间；[UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)立即更新进程内值，异步写入磁盘。这是 2026-09-08 核对的官方 API 契约，不是本轮运行测量。

当前 Extension 仅在启动和收到变更信号时请求快照，没有周期校验或菜单打开时拉取。因此，由当前机制不能推导出规定时间内必定同步；“保存配置完成”也不等于偏好已同步落盘或 Finder 副本已更新。主应用通知和监听恢复信号都应理解为重新查询的机会。

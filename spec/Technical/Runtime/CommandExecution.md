# 命令执行边界

本文件定义 Finder Feature、跨进程命令和主应用 Handler 之间的类型关系。各功能自身的系统 API 与运行时失败见[功能技术决策](../Features/Main.md)。

## 类型对齐

`ContextCommandFeatureID` 是用户配置、跨进程信封和主应用 Handler 共用的功能身份；`ContextCommandDescriptor` 为该功能提供共享名称、图标和运行依赖。运行依赖来自命令业务声明，图标独立表达视觉来源；外部应用命令从唯一应用声明派生执行依赖与产品图标。一个 Feature 可以贡献单个 Action，也可以贡献包含叶子、子菜单和分隔线的完整菜单子树；Action 只在所属 Feature 内拥有局部身份，配置和执行仍以 Feature 为单位，叶子图标的选择不改变所属功能的运行依赖。Finder 对菜单树的过滤和规范化见[菜单语义](../Platform/Finder/ContextMenus.md#菜单树与启用状态)。

每个 Finder Action 从已经冻结的语义快照直接构造其功能专用的 `ContextCommandPayload`。命令类型只表达对应 Handler 能处理的有效目标，不继续携带可形成无关 Finder 场景的通用上下文。

类型擦除只发生在组合与进程边界：Extension 把具体命令封装为带 Feature ID 的 `ContextCommandEnvelope`；主应用的不可变 Handler 注册表按同一 ID 找到唯一具体类型并解码。重复注册属于组合错误并以 precondition 暴露；认证后的未知 ID 或无效 payload 属于输入失败，记录后丢弃，不构造半有效调用。

## 副作用隔离

通用执行框架只固定以下边界：

```text
类型化 Command
  → Handler.execute
  → 不可变 Outcome
  → MainActor present
```

`execute` 承担可以离开主线程的工作；`present` 是界面以及剪贴板、Finder 结果选择等必须位于主线程的输出副作用边界。后台执行阶段需要反馈的可预期失败进入 Outcome，呈现阶段自身可能发生的系统失败则在该边界分类和反馈。

只有功能确实存在可独立表达的决策时，`execute` 内部才进一步采用：

```text
读取系统事实 → makePlan 形成类型化计划或失败 → 执行副作用
```

这是副作用隔离原则的具体体现，但不是要求每个简单操作都创建 Plan 或同名方法。排他文件创建等必须由一个系统调用同时完成判断和写入的操作保持完整，不拆成预检再执行。只能由注册错误或类型错配造成的不可能状态不增加静默兜底。

## 任务生命周期与并发

Router 在恢复完整类型化调用后才为其生成主应用本地 `requestID` 并登记独立 Swift Task。该 ID 关联进度、日志和反馈，不是 IPC 请求编号。

不同请求不经过跨功能全局串行队列；等待参数的命令也不阻塞其他请求。只有具体功能存在真实的顺序、容量或共享资源约束时，才由该功能在自身边界增加局部调度。Router 释放时取消仍由它持有的任务；进程被终止则直接结束工作，不承诺运行取消清理。协作取消和进度由[命令进度](CommandProgress.md)定义。

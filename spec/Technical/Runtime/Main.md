# 运行时边界

本目录记录两个产品进程之间以及主应用内部的稳定职责。产品行为以[需求](../../Requirements/Main.md)为准，构建身份和文件授权分别见[构建身份](../Delivery/BuildIdentity.md)与[文件访问](../Platform/FileAccess.md)。

## 职责

- **Finder Extension** 解释 Finder 事件、构建菜单、冻结语义上下文，并从中构造每个功能所需的最小类型化命令。它保持 App Sandbox，不执行产品文件操作，也不呈现业务结果。
- **主应用** 是菜单配置真相源、命令执行端和反馈出口。它负责文件系统、剪贴板、Launch Services、业务窗口和 Finder 结果选择等副作用。
- **ECMenuShared** 保存两个二进制必须一致的领域契约与无场景原语，不保存 Finder 菜单对象、主应用副作用或产品注册表。

```text
Finder 事件
  → Extension 语义快照
  → Feature 构造类型化命令
  → 已认证 IPC
  → Router 恢复类型化 Handler
  → 执行并形成 Outcome
  → 主应用统一呈现
```

## 导航

- [应用生命周期](ApplicationLifecycle.md)：配置会话、后台宿主、登录项与恢复边界。
- [IPC](IPC.md)：点对点投递、认证、framing 与失败语义。
- [命令执行](CommandExecution.md)：Feature、Action、Handler、并发与副作用隔离。
- [命令进度](CommandProgress.md)：进度的平台边界、窗口所有权和取消契约。
- [菜单配置](MenuConfiguration.md)：配置真相源、Extension 副本和更新同步。

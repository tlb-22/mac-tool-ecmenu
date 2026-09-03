# Finder Extension 生命周期

主应用恢复边界见[应用运行生命周期](../../Runtime/ApplicationLifecycle.md)，构建身份见[构建身份](../../Delivery/BuildIdentity.md)，通用证据范围见[平台边界](../Main.md)。

## 打开 URL

`FIFinderSyncController` 继承 `NSExtensionContext`。其 `open(_:completionHandler:)` 只请求 host 代为打开 URL，completion 仅返回成功布尔值；SDK 没有承诺 host 接受请求，也没有提供主应用启动或业务接管完成的信号（macOS 26.5 SDK `FinderSync.h:14–19`、`NSExtensionContext.h:24–25`）。

项目于 2026-08-21 在 macOS 26.6.1（25G76）实测：主应用未运行时，Finder Extension 通过该入口打开应用自定义 URL，completion 返回 `false`，主应用没有启动。同一 URL 能由其他进程通过 `NSWorkspace.open` 打开，不代表 Finder host 的 Extension 入口具有相同行为。

因此项目不把自定义 URL 作为命令入口或可靠冷启动通道，也不把 completion 解释为命令已通过 IPC 发送或执行。平台升级后应重新验证这一 completion 及其实际启动结果。

## 启用、登记与运行

`FIFinderSyncController.isExtensionEnabled` 只表示用户是否启用了 Extension（`FinderSync.h:115–118`）。`showExtensionManagementInterface()` 只打开系统管理界面，不返回设置是否改变；应用重新 active 后需要再次读取状态。

用户启用选择、Launch Services/PlugInKit 登记的应用路径和当前 Extension 进程是三个独立状态。Bundle identifier 是系统登记身份；多个父应用嵌入同一 Extension 身份时，系统可能保留并列记录、选择已经失效的路径，进而使管理界面或加载状态异常。诊断副本若不测试 Extension，应移除 `Contents/PlugIns`；确需测试时，父应用和 Extension 必须使用成对的独立身份。

Debug 与 Release 使用不同身份，但同时启用时仍会贡献重复菜单。项目脚本负责让所选环境只有一个 Extension 处于启用状态，并验证登记路径和运行进程；具体刷新与切换步骤见[开发脚本](../../../../scripts/Main.md)。

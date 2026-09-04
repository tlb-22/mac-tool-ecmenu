# 自动化脚本的用户焦点恢复

自动化可以临时激活 ECMenu、Preview 或 Finder，但不应在结束后把用户留在这些窗口中。焦点恢复覆盖会驱动界面的非交互脚本；`preview-ui.sh` 的产物本身是一个供人操作的前台窗口，因此不在此范围内。

## 稳定路径

最外层脚本在等待共享操作锁之前，通过 `NSWorkspace.frontmostApplication` 记录前台应用的 PID、启动时间、bundle identifier 和可执行文件路径。它随后以会话标记重新执行原命令；同一调用链中的子脚本看到该标记后直接运行，不再捕获或恢复焦点。

原命令退出时，先执行其自身的进程、窗口、语言和偏好恢复，再由最外层包装器请求原应用重新激活。包装器通过独立进程组运行完整子进程树；收到 HUP、INT 或 TERM 时把信号转发到该进程组，等待子脚本清理后才恢复焦点。恢复目标必须仍是同一 PID、非空且相同的启动时间及稳定身份，避免 PID 复用后激活无关进程。Finder 是唯一例外：截图和环境切换会按设计重启 Finder，原进程消失时可以选择 bundle identifier 与可执行路径唯一匹配的新 Finder 进程。

普通应用已经退出时跳过恢复，不重新启动应用；没有前台应用的 CI 或无界面会话也正常执行原命令，只是不建立恢复目标。恢复失败会使原本成功的脚本失败；原命令已经失败时保留其退出状态，并在独立日志中报告恢复错误。

## 平台契约与证据边界

Apple 将 `NSWorkspace.frontmostApplication` 定义为当前接收键盘事件的应用；`NSRunningApplication.activate(options:)` 用于请求激活运行中的应用。实现使用空选项，不请求同时展开该应用的所有窗口，并在主 RunLoop 上等待后同时核对 `isActive` 与当前前台 PID，而不把 API 的同步返回值当成已经完成切换。[NSWorkspace.frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) · [NSRunningApplication.activate(options:)](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)) · [NSApplication.ActivationOptions](https://developer.apple.com/documentation/appkit/nsapplication/activationoptions)

Xcode 26.6 SDK 的 `NSRunningApplication.h` 将 `activateIgnoringOtherApps` 标记为 macOS 14 起已弃用且不再生效，因此它不能作为增强激活的后备路径。项目也不使用 Accessibility 或私有 Space API；焦点恢复本身不增加系统授权要求。

项目对公开 AppKit API 表面的调查结论是：它只允许激活应用，没有选择指定 Space 的接口。因此自动验证“原应用重新成为前台”，不能从代码断言当前 Space 编号。2026-09-04 在 macOS 26.6.1（25G76）、Xcode 26.6（17F113）与 Visual Studio Code 1.136.1 上实测：从全屏 VS Code 切到另一应用后，对原运行实例调用 `activate(options: [])` 会返回原 VS Code 全屏 Space；完整 README 截图链路结束后也恢复为启动前同一 PID 的 `Code`，且嵌套脚本没有提前恢复。当同一应用在多个 Space 中拥有多个窗口时，具体显示哪个窗口仍由 macOS 的窗口与 Mission Control 状态决定。[在 Mac 上的多个空间中工作](https://support.apple.com/guide/mac-help/mh14112/mac)

## 已排除的路径

- 先激活辅助进程再交还焦点：命令行辅助进程作为 accessory application 时未可靠成为前台，不能提供稳定的交接基础。
- `activateIgnoringOtherApps`：当前 SDK 已明确声明无效。
- `NSWorkspace.openApplication`：包含启动或重新打开应用的语义，会把已退出的普通应用重新拉起，不符合恢复同一运行实例的边界。
- Accessibility 或私有 Space 控制：为此目的扩大权限或依赖非公开接口不合理，也不能形成可维护的产品契约。

# 测试期间的 Finder 窗口保持

`test.sh` 与 `test-integration.sh` 在最外层记录 Finder 窗口，等待子测试清理和用户焦点恢复完成后，再核对窗口集合。成功、失败和可处理的信号中断都执行核对；窗口变化使原本成功的测试失败，测试本身已经失败时保留其退出码。快照与诊断保存于本次运行的 scratch 目录。

窗口检查会话必须包住焦点恢复会话，入口拒绝反向嵌套。两层包装器在清理期间忽略后续终止信号，使进程组收到信号后再次转发到父子进程时，不会提前中断窗口或焦点恢复。

## 检查边界

窗口身份使用当前用户会话内的 `CGWindowID`，比较集合而不是数量、标题或前后顺序。新增、丢失和等量替换都会形成差异；临时打开后正确关闭的窗口不影响最终结果。检查覆盖 Finder 的普通层窗口，包括最小化及其他非屏幕上的窗口，排除桌面元素。它不验证已有窗口的目录、标签页、选择或位置。

Finder 重启后窗口标识可能变化，因此后台 IPC 集成测试只启动当前 Debug 主应用，用隐藏文件命令验证真实落盘变化。需要刷新 Finder、触发真实菜单和验证结果选择的流程，使用独立的运行与菜单验收入口，窗口归属要求见 [Finder 菜单自动截图](FinderMenuCapture.md)。

检查器只记录差异，不据此关闭窗口。运行期间用户手动开关 Finder 窗口也会形成差异，单凭开始、结束快照无法判断创建者。没有 Quartz GUI 会话时明确报告跳过；会话在测试期间消失或出现则报告无法保持原现场。

## 平台契约

Apple 将 `CGWindowID` 定义为用户会话内的唯一窗口标识。`CGWindowListCopyWindowInfo` 可返回窗口编号、所属进程和窗口层级；无 GUI 会话或 WindowServer 不可用时返回 `nil`，与查询成功但结果为空不同。[CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))

Apple 在 WWDC19 说明，该接口不会触发屏幕录制授权提示；未授权时过滤窗口标题等敏感元数据。检查器只读取编号、进程和层级，不读取标题、图片或 Accessibility，因此不增加辅助功能或屏幕录制权限要求。[Advances in macOS Security](https://developer.apple.com/videos/play/wwdc2019/701/)

Xcode 26.6 的 macOS 26.5 SDK `CGWindow.h` 明确 `optionAll` 包含屏幕内外窗口，`excludeDesktopElements` 排除桌面元素。系统升级后应重新验证 Finder 的窗口层级、最小化窗口枚举和异步关闭行为。

## 项目观察

2026-09-05 在 macOS 26.6.1（25G76）已有五个 Finder 普通窗口的桌面会话中，完整测试与 IPC 集成测试结束后的窗口 ID 集合均与开始时相同。把不存在的窗口编号加入隔离基线后，真实检查器报告该编号丢失、返回失败并保存结束快照；该失败路径验证没有操作实际窗口。

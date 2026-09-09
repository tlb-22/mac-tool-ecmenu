# 测试期间的 Finder 窗口保持

`test.sh` 与 `test-integration.sh` 在最外层记录 Finder 窗口，等待子测试清理和用户焦点恢复完成后，再核对窗口集合。成功、失败和可处理的信号中断都执行核对；窗口变化使原本成功的测试失败，测试本身已经失败时保留其退出码。快照与诊断保存于本次运行的 scratch 目录。

窗口检查会话必须包住焦点恢复会话，入口拒绝反向嵌套。两层包装器在清理期间忽略后续终止信号，使进程组收到信号后再次转发到父子进程时，不会提前中断窗口或焦点恢复。

## 职责与源码映射

| 职责模块 | 核心类型或脚本与源码入口 | 输入、输出与状态所有权 |
|---|---|---|
| 测试保护会话 | [finder-windows.sh](../../scripts/lib/finder-windows.sh) 接入，[with-finder-windows-checked.sh](../../scripts/lib/with-finder-windows-checked.sh) 执行包装 | 测试命令 → 构建检查器、捕获基线、等待测试与焦点清理、核对结束快照；包装器持有本轮路径、子进程和原退出码，以 `trap` / `kill` / `wait` 处理退出与信号 |
| 系统采样与检查入口 | `FinderWindowCheck` · [FinderWindowCheck.swift](../../Tests/FinderWindowPreservation/FinderWindowCheck.swift) | `capture` / `verify` 参数与快照路径 → JSON 快照、差异诊断及退出码；通过 `CGWindowListCopyWindowInfo` 与 `NSRunningApplication` 读取当前事实，使用 `Data` 和 JSON 编解码保存本轮证据 |
| 快照与比较规则 | `FinderWindowSnapshot` / `FinderWindowComparison` / `FinderWindowStability` · [FinderWindowSnapshot.swift](../../Tests/FinderWindowPreservation/FinderWindowSnapshot.swift) | 不可变窗口集合 → 相同、差异或 GUI 会话变化；比较是纯值计算，连续采样规则只持有上一次快照 |

纯规则验证见 [FinderWindowSnapshotTests.swift](../../Tests/FinderWindowPreservation/FinderWindowSnapshotTests.swift)，包装器的嵌套、退出码与信号处理验证见 [FinderWindowGuardTests.py](../../Tests/DevelopmentScripts/FinderWindowGuardTests.py)。二者由 [test.sh](../../scripts/test.sh) 执行。

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

2026-09-08 在 macOS 26.6.2（25G83）的真实子菜单验收中，Quartz 普通层集合曾新增两个编号；随后其中一个消失，另一个对应不在屏幕上、标题为空、尺寸为 64×64 的 Finder 窗口。后续菜单创建验收的 AX 浏览器窗口计数前后均为零。因此，普通层编号差异不能单独证明遗留了文件浏览器窗口；真实菜单验收还需核对已认领窗口的关闭结果和 AX 浏览器窗口集合。当前检查器仍保留严格的层级与编号比较，不用标题、尺寸或可见性猜测并过滤窗口。

# Finder 菜单自动截图

运行入口见[开发脚本](../../scripts/Main.md#finder-菜单截图)，生产菜单语义见[菜单语义](Platform/Finder/ContextMenus.md)。本文记录真实 Finder 菜单自动化中无法从单个源码位置恢复的平台事实、设计边界和失败经验。通用证据范围见[平台边界](Platform/Main.md)。

## 核心结论

- 截图对象必须是 Finder host 正在显示的真实菜单；重建相似界面不能验证 Extension 的实际菜单链路。
- Accessibility 负责交互、所有权和状态验证，ScreenCaptureKit 只捕获已经确认的独立菜单窗口。生产 Finder Extension 不包含截图分支。
- Finder 是全局、异步 GUI 状态。可靠性来自“动作前订阅、精确认领、截图前后验证、只清理本轮 UI”，不能来自固定等待或对前台窗口的猜测。
- 场景按业务所有权拆分：通用上下文在 `Contexts/`，命令特有的场景或期望在各自 `Features/`，Composition 只聚合，通用 `Support/` 不知道具体命令。

## 已排除的方案

| 方案 | 失败原因与保留结论 |
|---|---|
| 按屏幕矩形截图，再裁切到菜单边界 | 半透明菜单已经与后方 Finder 或桌面合成；裁切不能恢复窗口 alpha。必须捕获菜单自身的独立窗口。 |
| 重建菜单，或向顶层 ContextMenu、生产 Extension 注入截图场景 | 无法证明 Finder host 的真实结果，也会把命令特有逻辑扩散到组合层。截图定义留在测试侧，命令期望归所属 Feature。 |
| 复用当前窗口、按路径或单次 focused 状态推断所有权 | 容易操作或关闭用户窗口，也曾造成超时和窗口遗留。窗口必须从触发前注册的 created notification 中认领，并验证精确 AX 身份。 |
| Finder 激活后无条件调用带 Command-N 快捷键的菜单项 | Finder 在“未激活且零窗口”时会因激活自行创建窗口；再次新建会多开窗口。该初始状态必须直接认领激活产生的窗口。 |
| 动作后才观察，或把 `cannotComplete` 当作失败后重试 | 会错过短暂通知，或重复执行其实已经发生的动作。先注册 observer，再观察 UI 事实。 |
| 用通用 `AXConfirm`、默认按钮或取消按钮替换 Return/Escape | “前往文件夹”sheet 在验证环境中没有稳定、唯一且能完成同一流程的控件。保留严格焦点约束下的 Return/Escape，不为形式上的纯 AX 改写已验证路径。 |
| 直接写入项目多选，或不限制范围地调用带 Command-A 快捷键的菜单项 | Finder 项目视图不稳定接受直接写入的选择；全选还可能带入非场景文件。先点击并验证首项，只在 fixture 覆盖目录全部项目时调用 Finder 的全选 action，随后读取 `AXSelectedChildren` 验证。 |
| 菜单出现后立即截图，或只隐藏截图光标 | 隐藏光标不会清除已有 hover，菜单也可能尚未稳定。先把指针移出菜单，再取得连续一致的菜单快照。 |

## 平台契约

Xcode 26.6 附带的 macOS 26.5 SDK 声明：

- `AXWindowCreated`、`AXSheetCreated`、`AXMenuOpened` 和 `AXMenuClosed` 通知分别携带对应的 Accessibility element（`AXNotificationConstants.h:108–116, 162–165, 208–220`）。
- `AXUIElementPerformAction` 返回 `cannotComplete` 时，动作可能已进入目标应用的模态处理，并不证明动作失败（`AXUIElement.h:315–331`）。
- `SCContentFilter.initWithDesktopIndependentWindow` 只捕获传入的独立窗口（`SCStream.h:142–146`）。`SCScreenshotConfiguration` 默认按被捕获内容的像素尺寸输出，`ignoreShadows` 控制是否忽略窗口阴影，子窗口默认包含（`SCScreenshotManager.h:45–89`）。
- `SCScreenshotManager.captureScreenshot` 从 macOS 26.0 起按 filter 和 configuration 返回 `SCScreenshotOutput`，其中包含所请求的 SDR 或 HDR `CGImage`（`SCScreenshotManager.h:102–124, 163–178`）。

## 项目观察

以下结论于 2026-09-04 在 macOS 26.6.1（25G76）、Xcode 26.6（17F113）下验证，不代表 Apple 对未来版本的承诺：

- Finder 右键菜单同时暴露为 `AXMenu` 和可分享的 `SCWindow`。按“在屏幕上、Finder PID、AX 菜单 frame”联合匹配并要求唯一，可以定位菜单窗口；标题和窗口枚举顺序不适合作为身份。
- desktop-independent filter 的 PNG 保留 alpha、菜单本体和自身阴影，不包含 Finder 窗口或桌面背景。项目显式保留阴影、排除子窗口并输出 SDR PNG。
- 新创建的 AX element 可能短暂返回 `cannotComplete`、属性未就绪或 element 已失效；通知负责保留对象身份，连续观测负责确认状态稳定，不能把所有错误静默重试。
- Finder 不活跃且没有窗口时，激活本身会创建第一个窗口。“前往文件夹”sheet 未稳定暴露可替代 Return/Escape 的 confirm/default/cancel 路径。隐藏截图光标不会清除菜单已有的蓝色 hover。
- 当前全部场景的连续运行最终都得到具有 alpha、无背景、无 hover 的图片；在初始没有 Finder 窗口时，运行结束后仍为零窗口。

macOS 或 Xcode 升级后，至少重新验证 Finder 的 AX 树、激活时的窗口行为、菜单 `SCWindow` 匹配、透明度与阴影，以及“前往文件夹”sheet 的交互路径。

## 稳定协议

1. 动作前注册 AX observer；`cannotComplete` 后观察目标 UI，不立即重复可能产生第二个窗口或菜单的动作。只认领通知中 role 为 `AXWindow`、identifier 为 `FinderWindow`、仍属于 Finder 窗口列表，并经连续观测同时为 focused 与 main 的唯一窗口；不借用或关闭用户原有窗口。
2. 按快捷键元数据定位 Finder 菜单栏中带 Command-Shift-G 的菜单项，并对其执行 `AXPress`；只有 Return/Escape 使用键盘事件。写入路径并确认文本框焦点后发送 Return。项目项按文件 URL 从 AX 树解析，点击前用系统级 hit-test 确认没有被遮挡，选择后读取实际值验证。
3. 在 `AXShowMenu` 前订阅菜单打开通知。移出指针后，以“Finder PID、frame、包含分隔项的全部标题”形成稳定快照；按 PID 与 frame 唯一匹配 `SCWindow` 并捕获独立窗口。
4. 截图后再次验证 Finder 前台、本轮窗口为 main、选择未变且菜单快照相同。成功或失败都只按 session 已拥有的状态关闭本轮菜单、sheet 和窗口；一个清理步骤失败时仍继续后续清理，同时返回最早失败。

真实 Finder 场景串行执行，并用进程锁排除其他截图任务。运行期间桌面必须已解锁，操作者不得切换焦点或操作 Finder；所有权、焦点、选择或菜单发生变化时，本次截图失败。

## 权限与 CI 边界

helper 需要 Accessibility 来读取和操作 Finder，需要“屏幕与系统音频录制”来读取共享窗口；权限仅属于开发工具，不改变 ECMenu 产品本身的权限需求。helper 的固定身份见[构建身份](Delivery/BuildIdentity.md)：脚本在真实截图前分别核对嵌入式 Bundle ID、code-signing identifier 和 Development Team，不能只检查构建设置中的 Bundle ID。

真实截图依赖已解锁桌面、当前 Finder 进程、当前启用的 Debug Extension 和前台焦点，因此不进入无人值守 CI。`--check` 只验证场景注册、fixture、双语命令 key、helper 编译和静态 TCC 身份配置，不能替代真实截图验收。

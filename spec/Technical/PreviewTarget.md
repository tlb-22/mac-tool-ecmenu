# 界面预览目标

界面预览由独立的沙箱 macOS App target 承载。它在单独进程中复用生产 renderer 和共享契约，只在开发边界注入合成状态；产品主应用不包含预览分支，预览应用也不启动 IPC、嵌入 Finder Extension、参与产品归档或改变正在运行的产品生命周期。

文件模板预览通过内存快照和操作回调覆盖列表、空清单与载入失败，不访问产品模板库。列表中的名称编辑只更新预览会话内的对应字段；打开和更换操作不访问外部应用或文件。

预览不是自动化 UI 测试。唯一 Composition 注册全部 Preview ID，稳定 runtime 解析 ID、验证注册唯一性并维持对应会话；各 Case 以独立 ID 固定一种可见状态，并复用生产呈现类型或呈现边界。完整测试保证 Preview target 可编译且入口可列出，可见结果仍由人工检查。

## 职责与源码映射

启动脚本把 Preview ID 与语言参数交给独立进程，runtime 从注册表选择 Case 并保活它返回的界面会话。批量截图时，runtime 另以窗口就绪和捕获后确认协议与脚本协作。

| 职责模块 | 核心类型或脚本与源码入口 | 输入、输出与状态所有权 |
|---|---|---|
| 构建、启动与截图编排 | [preview-ui.sh](../../scripts/preview-ui.sh)、[capture-previews.sh](../../scripts/capture-previews.sh) | Preview ID、语言 → 通过 `xcodebuild` 构建并启动独立产物；批量脚本持有捕获进程和输出文件，依据 `READY` 窗口编号调用 `screencapture -l` |
| 独立进程入口 | `ECMenuPreviewsApp` / `PreviewApplicationDelegate` · [PreviewApp.swift](../../Tests/ECMenuPreviews/PreviewApp.swift) | AppKit 启动通知 → 查询场景列表或呈现指定场景；入口保活代理并管理 `NSApplication` 事件循环 |
| 场景注册 | `PreviewComposition` · [PreviewComposition.swift](../../Tests/ECMenuPreviews/PreviewComposition.swift) | 具体 Case 类型 → 唯一的 ID 与呈现入口注册表；纯内存声明 |
| 会话与截图协议 | `PreviewRuntime` / `PreviewReadinessCoordinator` · [PreviewRuntime.swift](../../Tests/ECMenuPreviews/PreviewRuntime.swift) | 启动参数与注册表 → 当前 Case 会话或错误界面；runtime 保活会话，协调器在主 RunLoop 检查 AppKit 窗口焦点、编号与布局，并通过标准输出发布 READY 与结果，通过 SIGUSR1 接收截图完成信号 |
| 场景状态与生产界面装配 | [Cases/](../../Tests/ECMenuPreviews/Cases/)，设置页共用 `StatusPagePreviewSession` · [StatusPagePreview.swift](../../Tests/ECMenuPreviews/Cases/StatusPagePreview.swift) | 固定场景参数 → SwiftUI/AppKit 界面；各会话拥有内存状态与操作回调。README 场景在 [READMEStatusPagePreview.swift](../../Tests/ECMenuPreviews/Cases/READMEStatusPagePreview.swift) 通过 `NSWorkspace` 读取真实应用图标 |

生产页面和窗口入口见[核心界面入口](ViewCatalog.md)。同一主题的多个可见状态可以在一个 Case 文件中定义，共用该主题的参数和会话。

## 原生交互验证与平台证据

异步输入交接使用[真实模板页面测试](../../Tests/ECMenuTests/NewFileTemplates/Presentation/NewFileTemplateSettingsPageTests.swift)验证：在隐藏的 `NSWindow` / `NSHostingView` 中向实际名称控件发送鼠标事件，并通过窗口的原生 field editor 输入，检查控件身份、`firstResponder`、输入落点、空白点击退出及保存失败后的恢复。挂起保存的用例检查连续点击的最终目标、操作按钮可用性和页面进度状态；文件操作用例覆盖添加、更换和删除时的控件身份与外观、重复请求拦截、页面重建后保留操作锁，以及失败重试。测试只访问本进程自建窗口，不显示窗口、获取桌面焦点或要求辅助功能授权；固定内存快照的预览不覆盖异步交接。

项目观察（2026-09-08，macOS 26.6.2、Xcode 26.6）：SwiftUI 的 `AccessibilityNode` / `AccessibilityLazyLayoutNode` 实现了公开的 Objective-C 可访问性方法，但没有声明 `NSAccessibilityProtocol` 协议；按协议转换过滤子节点会遗漏真实控件。宿主测试通过原生视图树定位名称控件，经公开可访问性方法动态分派检查 SwiftUI 操作按钮。节点具体类名只用于说明本次观察，测试不依赖私有类或选择器，也不将该协议声明情况视为跨系统版本保证。

测试前置条件：每项原生页面测试先用 `AXUIElementCreateApplication(getpid())` 定位测试进程，再通过 `AXUIElementCopyAttributeValue` 查询 `kAXRoleAttribute`，要求返回 `.success` 和 `kAXApplicationRole`。输入仅为本进程 PID 与角色属性，输出为 AX 状态和应用角色；查询失败作为测试失败报告。随后在 1 秒截止时间内跨主循环读取操作按钮，缺失时报告已观察到的按钮与缺失标题。原生字段就绪不代表 SwiftUI 的按钮树已经建立。

项目观察（2026-09-09，macOS 26.6.2、Xcode 26.6）：[GitHub Actions 运行 34305654097](https://github.com/tlb-22/mac-tool-ecmenu/actions/runs/34305654097) 中六项按钮操作测试均读到空树。独立进程探针中，布局及调用窗口 `orderBack` 后均未建立 SwiftUI 节点，本进程角色查询后节点出现；在 `AXIsProcessTrusted() == false` 的沙箱进程中，该查询也成功。测试据此显式初始化自身的 AX 查询路径，保留隐藏窗口与节点就绪检查。Apple 的 [NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview) 契约提供 AppKit 桥接与可访问性访问接口；上述节点初始化行为属于此版本的项目观察，不是节点同步发布或跨版本时序保证。

## 语言与批量截图

启动脚本可向单次预览进程传入 `-AppleLanguages (en)` 或 `-AppleLanguages (zh-Hans)`，分别检查英文和简体中文；未指定时不覆盖系统语言。语言只存在于进程启动参数中，预览和产品界面无需维护额外的 Locale 状态。

批量截图脚本构建一次 Preview target，从注册表验证全部或调用方指定的场景，并串行捕获每个场景的英文和简体中文版本。Preview runtime 负责激活唯一可见顶层窗口；窗口成为 key window、完成布局和绘制，且窗口编号与尺寸跨一轮主循环保持稳定后，才通过标准输出发送 `READY <windowNumber>`。脚本按该窗口编号生成不含阴影的独立窗口截图，圆角外保持透明；截图完成后，runtime 再确认应用与窗口在整段捕获期间没有失焦，只保留通过确认的图片。截图不依赖辅助功能或外部模拟点击，批量截图与交互预览互斥运行。

README 设置页场景分别覆盖通用、右键菜单和文件模板三个页面，与状态覆盖场景使用不同 Preview ID：前者固定全部开关开启，并在 Preview 边界通过 Launch Services 严格读取所需外部应用的真实图标；后者继续保留未批准、未启用和应用缺失等状态。README 文件模板页面固定使用 TXT 与 MD 两条内存样例。两者只共享生产 renderer 与无副作用的预览会话，不向产品代码加入文档截图分支。

构建、启动与截图参数见[开发脚本](../../scripts/Main.md#界面预览)。

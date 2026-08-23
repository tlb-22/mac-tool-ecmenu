# Finder 集成边界

本文集中记录 Finder Sync 与 Finder 反馈 API 的平台语义。具体命令如何使用已经冻结的上下文，由对应的[需求](../Requirements/Main.md)和功能技术文档说明。

## 证据范围

- **SDK 契约**来自 Xcode 26.6（17F113）附带的 macOS 26.5 SDK。下文行号对应 SDK 内的 `FinderSync.h`、`NSWorkspace.h`、`NSExtensionContext.h`、`NSFileManager.h`、`NSMenu.h` 和 `NSMenuItem.h`。
- **项目观察**来自本项目的 Finder 手动验收。单元回归只锁定当前兼容解释，不构成 Finder 实际返回字段的证据。早期 Finder 原始回调日志与当时的系统版本没有作为仓库证据保留，因此依赖字段组合的结论必须在系统升级后重验。
- **项目设计**是基于上述事实形成的稳定约束，不代表 Apple 对未公开行为的承诺。

## 菜单种类与目标字段

### SDK 契约

`FIMenuKind` 描述 Finder 请求的自定义菜单种类，而不是由当前选择数量推断。三个 contextual case 表示 Control-click 位置，另有工具栏按钮菜单（`FinderSync.h:123–136`）：

| 类型 | Apple 定义的触发位置 |
|---|---|
| `contextualMenuForItems` | Finder 窗口中的一个项目或一组选中项目 |
| `contextualMenuForContainer` | Finder 窗口背景 |
| `contextualMenuForSidebar` | Finder 侧边栏项目 |
| `toolbarItemMenu` | Extension 工具栏按钮 |

`targetedURL()` 返回 Finder 当前 target，Apple 将其描述为用户 Control-click 的项目；`selectedItemURLs()` 返回当前 Finder 窗口的选择数组（`FinderSync.h:73–101`）。两者只保证在 `menuForMenuKind:` 或由该菜单创建的 action 中有效；对应 target 或 selected items 位于 Extension 管理范围之外时，相应 API 可以为 `nil`。工具栏菜单即使与管理范围无关也会请求 Extension 提供菜单（`FinderSync.h:144–165`），本产品在该类型中返回 `nil`。

Apple 没有声明 `selectedItemURLs()` 的数组顺序等同于 Finder 的可见排序。本项目保留 API 返回顺序，但不把该顺序提升为平台保证。

### 项目兼容解释

空白处仍有残余选择、以及通过多层 Finder 替身进入目录，是 container 解读必须覆盖的验收场景。当前边界按以下规则把原始字段解释成唯一语义；这是针对这些场景的兼容策略，不是 Apple 的字段组合契约：

| 菜单类型 | 形成的语义快照 |
|---|---|
| container | `selectedItemURLs().first`，为空时回退 `targetedURL()` |
| items | 非空的完整 `selectedItemURLs()` |
| sidebar | `targetedURL()` |
| toolbar | 当前产品不提供菜单 |

该选择顺序是本项目为上述验收场景采用的兼容设计，不是 Apple 的字段组合契约。当前仓库没有保留早期 Finder 原始回调日志，因此其正确性以本项目的人工验收为证据边界；系统升级后必须重新检查无选择、残余选择和替身嵌套三类背景菜单。

## 菜单生命周期与不可变快照

Apple 允许在对应 action 中再次读取目标字段。本项目仍在 `menu(for:)` 开始时一次性读取并形成 `.container`、`.items` 或 `.sidebar`，原因是菜单可见性和最终 action 必须解释同一次用户交互；action 发生时的 Finder 选择或窗口状态可能已经改变。

每个实际渲染的菜单叶子绑定独立的 Action 身份和不可变快照。后续菜单请求不得覆盖仍在显示的旧菜单上下文；当前实现用菜单项实例唯一的 `tag` 路由并消费该绑定。这用于消除 action 到达前又发生菜单请求时的覆盖风险，不能退化为“最新一次 Finder 状态”的单一可变缓存。

语义快照只表达 Finder UI 事件。文件是否存在、是否为目录、package、符号链接和权限均由具体功能在自己的边界读取。替身解析只能回答路径最终访问哪个对象，不能反推出用户在哪个 Finder 窗口背景打开菜单，因此不使用祖先匹配或替身反向搜索修正容器。

Finder 要求菜单 action 由 Extension principal object 提供（`FinderSync.h:144–165`）。Finder 还可能为 Open/Save 面板创建额外 Extension 实例（`FinderSync.h:167–179`），所以进程内菜单状态不能假定只有一个全局实例。

## 菜单过滤与操作状态

### AppKit 契约

`NSMenu` 默认使用自动菜单验证；该模式会忽略手动设置的 `NSMenuItem.isEnabled`，改为通过 target/action 和 `NSMenuValidation` 计算启用状态（`NSMenu.h:137–141`）。`NSMenuItem.isEnabled` 由 `NSMenuItem.h:88` 声明；菜单只对已启用项目触发匹配的键盘等价操作（`NSMenu.h:143–145`）。

### 项目设计

用户配置、冻结的 Finder 快照和 Feature 在本次构建读取的系统事实共同决定叶子是否进入布局。不可执行的叶子在创建 AppKit 菜单前即被删除，布局解析同时删除空子菜单和多余分隔线；所有实际渲染的叶子都绑定 action、唯一 tag 和同一份快照。

项目对每一层菜单关闭自动启用，并显式保持已过滤叶子可用，避免 AppKit 再按 responder chain 改写产品已经完成的判定。文件权限、只读卷等不稳定条件不在菜单阶段预检，执行时仍可能按错误策略失败。

## 菜单图标对齐

### AppKit 契约

`NSImage.alignmentRect` 是客户端可以用于布局的对齐元数据；其底边包含基线语义，其他边提供相应方向的对齐信息。`NSImage` 的绘制方法不会自动应用它，是否使用由客户端负责（macOS 26.5 SDK `NSImage.h:160–168`）。SDK 以 `NSButtonCell` 为可以利用该区域排除装饰并对齐主体的示例；当前 `NSMenuItemCell` 文档同时明确该类型已不再负责菜单绘制，因此不能用它推断 Finder host 一定采用相同布局。

### 项目观察与策略

项目于 2026-08-21 在 macOS 26.6.1（25G76）上使用 Xcode 26.6（17F113）和 macOS 26.5 SDK 检查到，系统菜单字体为 13pt、cap height 约为 9.16pt。相同字号和常规字重下，SF Symbol 的 `.small` 比例生成约 9pt 高的主体 `alignmentRect`；`photo` 与 `photo.badge.arrow.down` 的主体区域相同，后者只在主体右下方增加完整外框。具体完整尺寸会随渲染上下文发生约 1pt 的离散变化，不作为产品契约。

同次人工对比中，Finder Extension host 会把直接提交的非正方形 `NSImage` 拉伸进方形图标槽位：`eye` 被横向压缩，`text.document` 被横向拉宽。Finder 自带“快速查看”的可见 eye 约为 14×9pt，与 13pt、`.small` 的系统渲染一致；垃圾桶和信息图标也落在同一自然尺度。该测量只描述当前系统，不是 Finder 私有配置的公开契约。

同次 18pt 外壳实验中，Finder 会把完整的方形 `NSImage` 适配到原有图标槽，不会因其内层 `alignmentRect` 是 16pt 而保留内容大小。18pt 外壳因此使内部图形产生约 `16 / 18` 的统一缩小；这一结果说明 `alignmentRect` 不能在 Finder 菜单中作为不影响尺度的溢出预留区。

同期对 SF Symbols 系统渲染的人工对比中，带 badge 的变体保持主体位置和自然尺寸，只让附属图形向语义主体之外延伸。项目据此把源 `alignmentRect` 的中心直接平移到固定画布中心，不根据完整外框居中，也不施加第二次几何缩放。原始截图没有作为仓库证据保留，因此这些结论需在平台升级时重新验收。

Finder 菜单图标使用集中配置的系统字体与 Symbol 度量，画布根据菜单字体完整行高生成。渲染时只把源 `alignmentRect` 的中心平移到画布中心，不为 badge 增加外层画布，也不缩放以适应画布。超出边界的附属像素由 `NSImage` 画布直接裁切；输出图像的语义对齐已烘焙进像素，不再依赖 Finder 解释源 `alignmentRect`。Launch Services 返回的应用图标没有 SF Symbols 的字形度量，继续保持宽高比并居中适配到同一画布。应用在菜单判定与图标读取之间消失时，图标读取使用 SF Symbol 占位符降级；该竞态不改变已经冻结的菜单结构。

主应用全部设置图标共用由呈现层集中配置的一套 Symbol 度量和画布。渲染器与 Finder 采用相同的“自然尺寸、语义主体居中、不缩放适配、越界裁切”算法，但视觉参数由设置界面独立调整，不复制 Finder 的当前参数。导航和“通用”页使用可跟随 SwiftUI 前景色的单色 template；“右键菜单”命令预览使用分层色，应用图标保留原色并以同一画布等比居中且不放大。

`Shared/Rendering/AppKitIconCanvasRenderer.swift` 保存两个产品 target 必须一致的无场景图像变换：按源 `alignmentRect` 语义居中，以及不放大的等比画布适配。它只接收已经配置好的 `NSImage` 和调用端画布，不包含菜单对象、固定尺寸、颜色模式、缓存或应用查找。Finder Extension 与主应用继续在各自的 AppKit 边界生成源图并拥有视觉参数，因此两个呈现环境可以独立调整，而自然尺寸与语义居中算法只有一个实现。

## 管理目录与外置卷

### SDK 契约

`directoryURLs` 是 Extension 管理的根目录集合；Finder 对每个根及其全部子目录发送观察回调，并要求 Extension 每次启动时显式设置该集合，没有管理目录时也应设置为空集合（`FinderSync.h:26–35`）。

`FileManager.mountedVolumeURLs` 枚举当前可用挂载卷；`.skipHiddenVolumes` 排除隐藏卷（`NSFileManager.h:30–38, 102–104`）。`NSWorkspace` 分别提供卷挂载、卸载和重命名通知，并在通知信息中提供卷 URL（`NSWorkspace.h:298–316`）。

### 项目观察与策略

本项目观察到，只登记 `/` 时 Finder 不会在独立挂载的外置卷上提供菜单。Apple 没有承诺一个管理根会跨越挂载点。Extension 因而在启动时登记 `/` 和当前全部非隐藏卷根，并在卷挂载、卸载或重命名后重新枚举完整集合。

管理范围和实际访问是两条独立边界：`directoryURLs` 不属于文件系统授权，Extension 登记卷根不代表主应用获得读写权；文件操作仍受 TCC、POSIX 权限、只读文件系统和 SIP 约束。权限模型见[进程、交付与权限边界](ExecutionArchitecture.md)。

## Finder 结果选择

`NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)` 会激活 Finder 并打开窗口。根路径为空字符串时，文件在 main viewer 中选择；根路径非空时会打开新的 file viewer；文件路径为 `nil` 时只打开根目录而不选择项目（`NSWorkspace.h:48–50`）。

`NSWorkspace.activateFileViewerSelecting(_:)` 会激活 Finder，并打开一个或多个窗口选择给定 URL（`NSWorkspace.h:52–53`）。因此单一新文件优先使用空根路径的 `selectFile`，批量输出使用支持多个 URL 的 `activateFileViewerSelecting`。

空根路径只指定 main viewer，并不保证 Finder 不激活或不出现窗口；项目实测中 Finder 仍可能打开窗口。公开 `FIFinderSyncController` API 表面也没有“取得菜单来源窗口身份”或“写回该窗口选择”的接口。因此，不引入 AppleScript / Apple Events、辅助功能 UI scripting 等另一套受授权且脆弱的集成时，自动选择结果与“绝不出现 Finder 窗口”无法同时保证。公开契约只描述打开和选择，没有进入重命名模式的参数；本项目也不做输入模拟。

## Extension 打开 URL 与状态

`FIFinderSyncController` 继承 `NSExtensionContext`。其 Swift `open(_:completionHandler:)`、即 Objective-C `openURL:completionHandler:` 只请求 host 代为打开 URL，completion 只有一个成功布尔值；SDK 契约既没有承诺 host 必须接受请求，也没有提供主应用完成启动或业务接管的信号（`FinderSync.h:14–19`；`NSExtensionContext.h:24–25`）。

项目于 2026-08-21 在 macOS 26.6.1（25G76）中实测：主应用不运行时，Finder Extension 通过该入口打开主应用自定义 URL，completion 返回 `false`，主应用没有启动。同一 URL 能由其他进程通过 `NSWorkspace.open` 打开，不能证明 Finder host 的 Extension 入口具有相同行为。

因此项目不把自定义 URL 作为可靠冷启动或恢复通道，也不把该 completion 的成功值解释为命令已经通过 socket 完整发送或由主应用执行。当前命令执行依赖已经常驻的主应用；真实进程退出后的边界见[进程、交付与权限边界](ExecutionArchitecture.md#恢复边界)。

`isExtensionEnabled` 只表示用户是否启用了 Extension（`FinderSync.h:115–118`）。`showExtensionManagementInterface()` 只负责显示系统管理界面，没有返回用户是否改变了设置；Apple 建议主应用重新 active 后再次查询状态。启用、系统登记到哪份应用以及 Extension 进程是否正在运行是三种不同状态；本项目的构建脚本分别验证用户启用选择、当前 Debug 登记和进程状态。

项目调试曾因测试构建改变 Extension 身份而在“登录项与扩展”中产生多个并列条目。Extension bundle identifier 属于系统登记身份，所有本项目构建都必须保持稳定；重新构建只允许登记路径指向新的项目内产物，不能靠更换身份绕过旧登记。

项目于 2026-08-21 进一步观察到，把完整主应用复制成诊断探针时，如果副本仍内嵌相同 bundle identifier 的 Finder Extension，Launch Services 会同时保留两个父应用和两个同身份插件记录。`pluginkit` 可能只显示当前胜出的路径，但系统管理界面会丢失可管理条目，Finder 也可能不启动该 Extension。诊断副本不得保留生产 Extension 身份：无需测试 Extension 时应移除副本的 `Contents/PlugIns`；确需测试时必须为父应用和 Extension 使用成对的独立身份。探针结束后还应分别注销其 Extension 与父应用，不能只删除磁盘文件。

项目于 2026-08-22 在同一系统环境中实测：Archive、Release 与 Debug 产物曾同时留下三个已启用的同身份 PlugInKit 记录，胜出路径指向已经不存在的 Archive 产物；当前 Debug 记录虽然存在，Finder 仍不启动 Extension。重复执行 `pluginkit -a` 不会替换这些记录。项目的完整 Finder 刷新因此先逐路径移除全部同身份插件登记并注销旧父应用，再强制登记、启用且验证唯一的当前 Debug 路径；只有登记状态正确后才重启 Finder、触发受管目录并等待新的 Extension 进程。旧 Finder 与 Extension 的退出也必须有界等待，避免把正在退出的旧进程或尚未完成的冷启动当成刷新结果。

## 平台升级复验

升级 macOS 或 Xcode 后，至少重新验证：

- container 在无选择、残余选择和多层 Finder 替身中的两个原始 URL 字段；
- 连续构建不同菜单后，旧菜单 action 仍使用自己的快照；
- 顶层和各级子菜单都删除不可用叶子、空子菜单与多余分隔线，保留叶子均可发送 action；
- Finder 自带“快速查看”等图标仍与当前统一系统度量相协调；眼睛和文件等非方形 SF Symbol 保持自然宽高比，带 badge 的 Symbol 保持主体位置且附属图形完整；
- 已挂载卷、新挂载卷、卷重命名和深层目录的菜单覆盖；
- 单文件与批量结果选择是否激活或打开新的 Finder 窗口；
- Finder Extension 的 `openURL` 对主应用自定义 URL 的 completion 结果，以及该结果是否实际启动主应用。

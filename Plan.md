# ECMenu 架构设计

本文记录当前代码组织与功能扩展所遵循的架构边界。产品行为以 [`spec/Requirements/`](spec/Requirements/Main.md) 为准，实现选择以 [`spec/Technical/`](spec/Technical/Main.md) 为准。

## 架构原则

1. **先建立领域语言，再实现流程。** 用专门类型表达系统中的对象、关系与状态，让类型排除无效组合，而不是在字符串、布尔值和字典之间传递隐含约定。
2. **从系统目标向下递归分解。** 子系统、API、页面和步骤共同覆盖上层目标；每一层只暴露下层完成组合所需的信息。
3. **按一起变化的业务能力组织代码。** 一个用例的规则、状态和结果保持高内聚；只有出现独立概念、真实复用或不同变化原因时才拆分文件。
4. **契约先行，并让边界两端对齐。** 跨进程或跨模块操作拥有与交互方向一致的请求、结果和失败语义，调用端、共享契约和执行端使用可直接对应的命名与路径。
5. **把副作用推到边界。** 系统读取产生不可变事实，纯函数据此构造计划，执行器完成写入并立即把任意底层错误分类为领域结果，最终由单一出口呈现反馈。
6. **最小化可变源状态。** 只保存用户或外部事件真正改变的值，其余状态由纯函数推导；每份可变状态应有唯一所有者和明确生命周期。
7. **让失败、并发和资源生命周期成为设计的一部分。** 可预期失败使用类型化结果；独立任务并发执行，共享资源按实际顺序、容量、取消和清理需求建立策略。
8. **根据交互语义选择通信。** 不需要返回值的命令使用认证后单次单向发送，需要当前状态的配置使用请求/响应，需要生产者与消费者时间解耦时才使用队列。
9. **让测试结构对应系统结构。** 纯规则用单元测试，边界契约用编解码测试，运行 target 用边界测试，跨进程交付用可重复集成测试。

## 系统边界

```text
Finder
  → EnhancedContextMenuFinderExtension
  → Shared 类型化命令与传输契约
  → ECMenu 主应用
  → 文件系统 / 外部应用 / 剪贴板 / Finder 反馈 / 设置窗口
```

- **主应用**是常驻命令宿主、配置真相源、命令执行端和用户反馈出口。文件写入及外部应用启动由非沙箱主应用完成。
- **Finder Extension**只解释 Finder 瞬时上下文、声明并渲染菜单、构造命令，并向已经运行的主应用单次发送。它保持沙箱，不承载主应用业务执行。
- **Shared**只保存两端必须一致的领域契约、传输格式与无场景跨 target 渲染原语，不包含 AppKit 菜单、文件系统执行或产品总注册表。

代码分为两个业务类别：

- `ContextCommands`：Finder 右键触发的用户动作。
- `AppControl`：菜单配置、Extension 状态和系统设置入口等软件全局控制。

## 主应用生命周期

主应用使用单个长期存活的进程同时承载命令服务器和配置界面，并明确区分两个呈现状态：

- 配置会话打开时，`StatusPageWindowController` 拥有唯一 Status Page，应用使用 `.regular` 并显示在程序坞中。最小化窗口不关闭配置会话。
- 点击关闭按钮、按 `Command-W` 或选择 `Command-Q` 会关闭配置会话，应用切换为 `.accessory` 并从程序坞隐藏，但命令服务器、既有任务和业务窗口能力继续存在。
- 参数、错误和进度等业务窗口不改变配置会话状态，也不会单独使应用出现在程序坞中。
- 再次普通打开应用复用当前进程和同一个 Status Page，不建立第二个命令宿主。
- 已登记并获批准的主应用登录项在后续登录时建立同一个命令宿主，但初始进入 `.accessory`，不显示 Status Page 或程序坞图标；用户随后普通打开应用时再切换到配置会话打开态。

`AppDelegate` 拥有命令服务器、配置真相源、登录项适配器和 `StatusPageWindowController`，并集中解释初始启动来源、应用重新打开、窗口关闭与菜单命令。`LoginItemController` 只封装 `SMAppService.mainApp` 的登记和状态映射，不引入 Helper 或第二种宿主。SwiftUI App 入口只装配 delegate 和应用菜单，不隐式拥有第二个配置窗口。主进程遭强制退出、崩溃或注销后不存在执行端；Finder 命令失败并播放默认提示音，用户普通打开应用后恢复，或由已批准的登录项在后续登录时恢复后台宿主。

## 稳定机制、注册代码与功能切片

每个运行 target 的 `ContextCommands` 根目录保存稳定机制；`Features` 保存增量业务：

- 稳定机制负责 Finder 上下文解释、菜单值树、调用端 AppKit 视觉配置、类型擦除、认证传输、Router、任务生命周期和可选命令进度；两端相同的无场景画布变换由 `Shared/Rendering` 提供。
- `Features/FinderComposition.swift` 只按产品顺序注册 Finder Feature。
- `Features/ExecutionComposition.swift` 只按产品顺序注册主应用 Handler。
- `Features/<功能>/` 在 Shared、Finder Extension 和主应用三端保持路径对应。

两个 Composition 分别描述调用端能力和执行端能力，属于两个进程不可合并的最小注册。Shared 不维护第三份功能目录；测试使用不进入产品 target 的稳定 ID 基线验证两端配对。

## 声明式菜单模型

菜单使用两层身份：

- **Feature ID**是跨进程命令、用户配置和状态页使用的产品功能身份。
- **Action ID**由 Feature ID 与 Feature 内局部 ID 组成，只负责定位具体菜单叶子及其参数。

简单功能遵循 `SingleActionContextMenuFeature`，只声明可见性和命令构造，名称与图标来自共享 Command descriptor。复杂功能可以在同一个 Feature 文件内使用 `ContextMenuFeatureMenu` 声明 Action、分隔线和递归子菜单；同一种 Command 的不同 Action 可以携带不同参数。这样新增一个简单功能仍然只增加三端功能切片和两行注册，未来的多叶子功能也不需要伪装成多个 Feature。

Finder 菜单使用一次短生命周期求值，把冻结快照和同次构建共享的系统事实合并为叶子可见性。不可执行叶子在布局阶段删除；每个实际渲染的叶子取得唯一 `NSMenuItem.tag`，绑定“Action ID + 本次菜单语义快照”。后续菜单构建不会覆盖仍在显示的旧菜单上下文。

## Finder 语义上下文

Finder 原始 `FIMenuKind`、`targetedURL()` 和 `selectedItemURLs()` 只存在于 Extension 的 `FinderContextReader` 边界。跨进程只允许三种有效值：

```swift
.container(path: String)
.items(selection: FinderItemSelection)
.sidebar(path: String)
```

`FinderItemSelection` 保证路径集合非空并保留 Finder 顺序；快照使用显式 Codable 字段。存在性、文件或目录类型、权限和具体目标规则仍由各 Feature/Handler 读取，不进入共享上下文。

## 命令执行与副作用

每个 Handler 以完整用例为内聚单位，并遵循同一数据流：

```text
读取系统事实（副作用）
  → makePlan（纯函数，返回类型化计划或失败）
  → execute plan（副作用，立即分类底层错误）
  → Outcome / Report（不可变执行事实）
  → present（日志、提示音、弹窗或 Finder 反馈）
```

单目标全有或全无操作使用 `Result`；允许部分成功的批量操作使用包含成功项与问题集合的 Report。`Optional` 只表达正常缺席，例如菜单不显示。通用 Router 为每个已恢复命令建立独立 Task；具体功能只有出现真实顺序、容量或资源冲突时才增加局部调度策略。

Router 还为每次执行提供惰性进度 reporter。普通 Handler 不需要创建进度状态；长任务在真实工作开始时声明确定总数，在功能定义的安全边界推进计数并选择是否响应协作取消。主应用只为持续超过显示阈值的任务维护共享非模态窗口，不因进度而串行化命令。

图片压缩的设置领域值与可注入偏好存储位于 `ImageCompressionSettings.swift`，AppKit Prompt、窗口、表单和输入格式化位于 `ImageCompressionSettingsWindow.swift`。两者分别随设置语义和界面变化，不继续拆分；ImageIO 执行保持在图片压缩 Handler，直到出现第二个真实复用者。

## 开发界面预览

可视界面使用独立的 `EnhancedContextMenuPreviews` macOS App target，不向产品生命周期或日常 `run-debug.sh` 增加界面分支，也不把人工视觉检查伪装成自动化测试。

- `Previews/PreviewRuntime.swift` 是稳定边界，负责根据预览 ID 启动界面并保活会话。
- `Previews/PreviewComposition.swift` 只声明预览 ID 与对应入口。
- `Previews/Cases/` 中每个文件对应一个生产界面，并在文件开头集中声明任务数量、模拟进度等可调预览参数。
- 预览 target 复用生产 renderer 和共享契约，只注入合成状态；不复制界面布局，不启动产品命令服务，也不触碰真实配置或用户文件。
- `scripts/preview-ui.sh` 是唯一启动入口，只构建和替换独立预览进程。新增预览只增加一个 Case 文件和一行声明式注册。

## 跨进程投递语义

Extension 为每次用户动作创建不可变的命令请求，在双方运行态代码签名身份验证后向已经运行的主应用发送一次。客户端不自动重试，不等待接管回执或业务结果，也不保存待投递状态。传输不尝试启动主应用，也没有 URL 执行入口。

连接、对端验证、编码或完整写入失败时，Extension 记录错误并播放一次默认错误提示音。完整写入成功只表示本次点对点发送完成，不证明主应用已解码或执行该命令。主应用对通过认证的正文检查 schema，恢复已注册 Handler 的类型化 Invocation，并让 Router 登记独立 Task；无效或不兼容请求只记录并丢弃。

用户的每次点击都是一个独立请求。主应用缺席或瞬时发送失败时，本次点击结束，用户在宿主恢复后再次点击。命令请求保留显式 schema，不兼容版本直接丢弃；主应用与内嵌 Extension 始终作为同一应用版本成对交付，更新后由 Finder 重新加载 Extension，不提供跨 schema 兼容层。菜单配置是独立的状态查询，仍在已验证连接上使用请求/响应。完整信任边界见 [`spec/Technical/ExecutionArchitecture.md`](spec/Technical/ExecutionArchitecture.md)。

## 文件粒度准则

- 文件以完整用例或稳定机制为首要单位，不按行数拆分。
- 简单功能的 Plan、Outcome、纯规则、执行和反馈保留在同一个 Handler 文件。
- 公共代码必须拥有至少两个真实使用者和清晰所有权，不建立无边界的 `Utils`、`Helpers` 或 `Managers`。
- 短文件在表达独立平台适配器或共享契约时可以成立；长文件在主题单一且阶段边界清晰时也可以成立。
- 测试属于其生产代码所在 target；跨测试共享的项目目录边界集中在测试辅助类型中。

## 文件树

```text
EnhancedContextMenu/
├── EnhancedContextMenu/                         # 主应用 target
│   ├── App/
│   │   ├── EnhancedContextMenuApp.swift          # SwiftUI 入口、delegate 桥接与应用菜单
│   │   ├── AppDelegate.swift                     # 常驻宿主与配置会话生命周期
│   │   ├── ApplicationMetadata.swift              # 跨生产界面的 Bundle 显示元数据
│   │   └── FullDiskAccessSettings.swift          # 完全磁盘访问设置适配器
│   ├── AppControl/
│   │   ├── LoginItemController.swift             # 主应用登录项登记与系统状态映射
│   │   ├── MenuConfiguration/                    # 配置真相源
│   │   └── StatusPage/
│   │       ├── StatusPage.swift                  # 声明式配置页面
│   │       └── StatusPageWindowController.swift  # 唯一窗口所有权与关闭回调
│   └── ContextCommands/
│       ├── ContextCommandServer.swift             # 命令解码、恢复与路由
│       ├── ContextCommandExecution.swift          # Handler 注册、恢复、Router 与 Task
│       ├── ContextCommandProgress.swift           # 可选进度状态、协作取消与共享窗口
│       ├── FileNaming.swift                       # 跨功能文件冲突命名规则
│       ├── SystemError.swift                      # 系统错误快照与分类
│       └── Features/
│           ├── ExecutionComposition.swift         # 声明式 Handler 注册
│           ├── NewTextFile/
│           ├── CopyPath/
│           ├── Visibility/
│           ├── OpenInApplication/
│           └── ImageCompression/                  # Handler、Settings、SettingsWindow
├── EnhancedContextMenuFinderExtension/           # Finder Extension target
│   ├── App/FinderSync.swift                       # Finder 生命周期与监听范围
│   ├── AppControl/MenuConfiguration/              # 配置只读副本
│   └── ContextCommands/
│       ├── ContextCommandClient.swift              # 认证后单次单向命令发送
│       ├── ContextMenuFeature.swift                # Feature/Action 声明与类型擦除
│       ├── ContextMenuLayout.swift                 # 递归菜单值树与纯过滤
│       ├── FinderContextMenuController.swift       # 快照、渲染、图标与 action 路由
│       └── Features/
│           ├── FinderComposition.swift             # 声明式 Feature 注册
│           ├── NewTextFile/
│           ├── CopyPath/
│           ├── Visibility/
│           ├── OpenInApplication/
│           └── ImageCompression/
├── Shared/                                        # 两个产品 target 的共享契约与无场景原语
│   ├── AppControl/MenuConfiguration/
│   ├── ContextCommands/
│   │   ├── ContextCommandIdentity.swift
│   │   ├── ContextCommandTransport.swift
│   │   ├── FinderContext.swift
│   │   └── Features/<功能>/                        # 各功能 Command
│   ├── IPC/                                        # 定向 socket 协议、framing 与双向身份验证
│   └── Rendering/
│       └── AppKitIconCanvasRenderer.swift          # 参数化图标画布变换
├── Previews/                                      # 独立 EnhancedContextMenuPreviews target
│   ├── PreviewApp.swift                           # AppKit 应用生命周期
│   ├── PreviewRuntime.swift                       # ID 解析、呈现与会话保活
│   ├── PreviewComposition.swift                   # 声明式 Preview 注册
│   └── Cases/                                     # 合成状态与集中可调参数
│       ├── ContextCommandProgressPreview.swift
│       ├── StatusPagePreview.swift
│       └── ImageCompressionSettingsPreview.swift
├── Tests/
│   ├── CompositionExpectation.swift               # 测试期两端配对基线
│   ├── EnhancedContextMenuTests/                  # 主应用、Shared 与 Handler 测试
│   │   ├── App/ApplicationPresentationTests.swift # 配置会话状态转换测试
│   │   ├── AppControl/LoginItemControllerTests.swift # 登录项状态与副作用边界测试
│   │   └── ProjectTestDirectory.swift             # 项目内 fixture 边界
│   ├── EnhancedContextMenuFinderExtensionTests/
│   │   ├── ContextCommandClientTests.swift       # 单次单向发送测试
│   │   └── ContextCommands/                       # 菜单值树与 Feature 规则测试
│   └── Integration/ContextCommandSender.swift     # 真实进程命令发送与配置查询入口
├── scripts/
│   ├── run-debug.sh
│   ├── preview-ui.sh
│   ├── test.sh
│   └── test-integration.sh
├── spec/
└── Plan.md
```

## 三端对应关系

| 功能 | Shared Command | Finder Extension Feature | 主应用 Handler |
|---|---|---|---|
| 新建 TXT | `NewTextFile/CreateNewTextFileCommand.swift` | `NewTextFile/CreateNewTextFileFeature.swift` | `NewTextFile/CreateNewTextFileHandler.swift` |
| 拷贝路径 | `CopyPath/CopyPathCommand.swift` | `CopyPath/CopyPathFeature.swift` | `CopyPath/CopyPathHandler.swift` |
| 隐藏 / 显示项目 | `Visibility/VisibilityCommands.swift` | `Visibility/VisibilityFeatures.swift` | `Visibility/VisibilityHandlers.swift` |
| 压缩图片 | `ImageCompression/CompressImagesCommand.swift` | `ImageCompression/CompressImagesFeature.swift` | `ImageCompression/CompressImagesHandler.swift` |
| 进入外部应用 | `OpenInApplication/OpenInApplicationCommands.swift` | `OpenInApplication/OpenInApplicationFeatures.swift` | `OpenInApplication/OpenInApplicationHandlers.swift` |

## 新增功能规则

新增一个简单右键功能只需要：

1. 在三端对应的 `Features/<功能>/` 增加 Command、Feature 和 Handler。
2. 在 Command descriptor 中声明唯一 Feature ID、产品名称、图标和可选应用依赖。
3. 在 Finder Composition 与 Execution Composition 各增加一行。
4. 在对应 target 增加纯规则、契约和边界测试。

同一功能需要多个菜单叶子时，在该 Feature 内声明 Action 子树和参数构造；配置与执行端仍只注册一次 Feature/Handler。稳定机制不增加产品功能分支。

## 验证边界

- `./scripts/test.sh` 执行两个正式 XCTest target，并额外编译独立 Preview App target、验证其注册表可列出；Xcode Derived Data 位于 `.derivedData/`，单次测试工作目录和显式保留的结果位于 `.artifacts/scratch/tests/`。
- `./scripts/test-integration.sh` 使用独立 Sender 验证已经运行的主应用能够接收一次真实进程单向命令并执行，以及在独立请求/响应连接上返回菜单配置；它不覆盖 Finder 点击或主进程缺席后的启动。
- 生命周期单元测试验证普通启动、登录启动、配置会话开关和窗口关闭事件的状态转换；登录项测试验证系统状态到开关与批准提示的映射，不固定视觉参数。关闭按钮、`Command-W`、`Command-Q`、最小化、业务窗口、登录启动及强制结束后的恢复边界按 [`scripts/Main.md`](scripts/Main.md#生命周期人工验收) 人工验收。
- `./scripts/preview-ui.sh <preview-id>` 在独立预览进程中使用假状态启动指定的真实界面，不执行对应业务命令或中断产品进程。
- Finder Extension 源码变化后使用 `./scripts/run-debug.sh --refresh-finder`，并确认系统只登记项目 Debug 产物且两个进程各有一个实例。
- 具体功能验收矩阵位于相应 Requirement 与 Technical 文档，不在本文件重复维护。

# 目标模块契约与目录

以下名称是责任草案；实施时可以沿用现有类型名称。除明确提出的内部结果类型调整，保持已发布的命令身份、路径编码、偏好键和模板存储 schema。

## 能力与运行模块的契约

| 模块 | 输入 → 输出 | 唯一所有者 / 外部 API |
|---|---|---|
| 应用 Composition | 构建身份和生产适配器 → 已连接的依赖图 | 持有配置、模板 actor、Router、ProgressCenter、IPC、配置窗口；无业务决策；AppDelegate 继续适配 AppKit 生命周期 |
| 设置外壳 | 已注入的页面与导航状态 → 页面选择/显示 | 拥有状态页窗口和导航；SwiftUI、NSWindow、界面偏好 |
| 模板管理 | 导入/改名/更换/删除意图 → 提交结果；读取 ID → 模板内容快照 | actor 唯一持有已提交索引；管理会话持有草稿和操作生命周期；平台实现使用 FileManager、Darwin、FileHandle、Data |
| 菜单配置 | 总开关/Feature 可见性意图 → 当前配置 | Controller 持有进程内配置，UserDefaults store 负责偏好恢复与保存；系统更新无同步落盘回执 |
| 菜单快照提供者 | 当前开关读取边界 + 模板菜单读取边界 → 完整 MenuConfigurationSnapshot | 只投影，不复制第二份持久化真相；模板不可用仍返回当前开关 |
| 菜单变更发布者 | 配置已更新 / 模板索引已提交 / 管理页加载或重试成功 / IPC 已开始监听 → 失效提示 | 调用 DistributedNotificationCenter；无正文、无可靠到达承诺；保留模板可用性恢复的提示入口 |
| 新建文件用例 | 目录路径 + 模板 ID → CreatedFile 或模板/目标失败 | 取得一次内容值，再调用排他写入边界；用例不持有模板缓存 |
| 复制路径用例 | 非空有序路径 → Copied 或目标/剪贴板失败 | `lstat` 与 MainActor PasteboardWriter；实际写入后才返回成功 |
| 可见性用例 | Selection + 类型绑定操作 → 批量报告 | 纯计划过滤点号项目，适配器写属性；每项结果独立 |
| 外部应用用例 | 单目标路径 + 固定应用定义 → 打开请求结果 | Workspace 适配器查询和打开；不使用 shell、CLI 或持久化应用路径 |
| 图片压缩用例 | 图片选择 + 参数会话 → 批量报告 / 参数取消 | 每个批次持有确认参数和进度；ImageIO 与文件适配器产生结果 |
| 命令运行时 | 有效命令信封 → Invocation → Task 生命周期 | Router 独占在途任务；调用功能用例后统一结束进度并调用反馈策略 |
| 进度协调 | begin/advance/finish/取消意图 → 不可变可见快照 | Center 唯一拥有事实、显示延迟和用户隐藏集合；窗口只发送交互事件 |
| IPC 请求适配 | 已认证请求 → 调用用例入口或查询快照 | 监听/连接各自唯一拥有 socket；IPC 层不组装模板业务状态、不承担命令完成判定 |
| Finder 菜单 | Finder 事实 + 菜单副本 → 语义 Action 树 → NSMenu | 菜单控制器唯一保留按 tag 区分的冻结动作，维持有界淘汰语义；系统读取与 AppKit 渲染从纯 Feature 规则分开 |

窄边界可以使用已有的闭包结构，也可以在存在多个使用者或独立实现时用协议。抽象的目的在于明确副作用和替换验证，不是让每个内部函数都有接口。

## 三项需要先明确的内部结果

**模板变更结果。** 区分“提交前失败”“已提交”“已提交且清理存在问题”。已提交结果携带权威清单；清理失败不能伪装成修改未发生。发布者由这个结果触发一次失效提示，界面按操作类型呈现当前既有策略：删除清理问题可见，更换后的旧副本清理问题留在日志/后续清理。存储字节格式保持不变。

**复制路径结果。** `CopyPathPlan` 继续是纯计划；用例调用 PasteboardWriter 后返回 `Copied`、`TargetUnavailable` 或 `PasteboardWriteFailed`。剪贴板清空和写入的现有非事务语义如实保留。该接口处理当前代码可观察的返回值，不声称封装可以消除所有 AppKit 异常。

**菜单快照。** 保持 `available([])` 与 `unavailable` 的区别；快照以各所有者提供的当前已提交事实组装，不增加全局锁或假设跨两个存储的原子事务。Extension 仍整体应用一个有效响应，并保持已有“拉取期间变更则丢弃该响应并重拉”的规则。有限时间收敛是独立产品决策。

管理页加载与显式重试成功也会请求发布，即使没有索引修改，以保留 `.unavailable` 恢复为可用清单的路径。首次读取触发的初始化/迁移提交经模板应用边界发布；普通 IPC 读取已缓存清单不发通知，避免“查询—通知—再次查询”的循环。读取边界需显式返回是否发生初始化/迁移提交，不另存一个可变发布标记。

## 建议目录

```text
ECMenu/
├── App/                              入口、生命周期、唯一依赖装配
│   ├── ApplicationComposition.swift
│   └── AppDelegate.swift
├── Settings/                         设置外壳、窗口、导航与页面装配
├── Features/
│   ├── ApplicationSettings/          登录项与系统设置入口、通用设置页
│   ├── MenuConfiguration/
│   │   ├── Application/              配置变更、快照投影、失效发布
│   │   ├── Persistence/              UserDefaults 读写
│   │   └── Presentation/             右键菜单设置页
│   ├── FileTemplates/
│   │   ├── Domain/                   模板元数据、名称规则、内容/变更结果
│   │   ├── Application/              操作协调、只读接口、提交结果发布
│   │   ├── Persistence/              actor、索引、文件副本、独立迁移
│   │   └── Presentation/             列表、文件操作会话、名称编辑与控件
│   ├── NewFile/                      用例与反馈；简单能力使用少量文件
│   ├── CopyPath/                     计划、用例、剪贴板边界、反馈
│   ├── Visibility/                   共用隐藏/显示规则、用例、属性边界、反馈
│   ├── OpenInApplication/            共用用例、Workspace 适配、反馈
│   └── ImageCompression/
│       ├── Domain/                   设置、计划、图像尺寸与结果
│       ├── Application/              参数会话和批量用例
│       ├── Persistence/              最后确认参数
│       ├── Platform/                 ImageIO / 像素处理与文件输出边界
│       └── Presentation/             参数窗口/表单和结果文案
├── CommandRuntime/                   类型恢复、Invocation、任务生命周期
│   └── Progress/                     进度事实、Reporter、Center
├── Feedback/                         通用警告与进度窗口适配
├── FileSystem/                       确实跨能力共用的冲突命名和错误快照
└── IPC/                              应用请求适配与监听生命周期

ECMenuFinderExtension/
├── App/                              FinderSync 与管理位置
├── Menu/                             上下文读取、菜单构建/渲染、动作绑定
├── Features/
│   ├── NewFile/
│   ├── CopyPath/
│   ├── Visibility/
│   ├── OpenInApplication/
│   └── ImageCompression/
├── MenuConfiguration/                只读副本、缓存和拉取协调
└── IPC/                              单向命令客户端

ECMenuShared/
├── Contracts/
│   ├── FileSystem/                   绝对路径和非空选择集
│   ├── Commands/                     Feature 身份、descriptor、payload/envelope
│   ├── MenuConfiguration/            开关值与完整菜单快照
│   ├── IPC/                          请求种类与跨进程值契约
│   └── Features/                     NewFile 等对应功能请求
│       └── FileTemplates/            仅模板 ID 与菜单描述
└── Platform/
    ├── IPC/                          端点身份、对端认证、framing、连接与监听
    ├── Rendering/                    共用 AppKit 图标画布原语
    └── Logging/                      共用日志身份

Tests/
├── ECMenuTests/                      跟随主应用能力/运行时边界
├── ECMenuFinderExtensionTests/       跟随 Extension 边界
├── ECMenuPreviews/                   复用生产呈现，内存注入
└── Integration/及其他工具测试          保留专用系统验收边界
```

NewFile、CopyPath、Visibility、OpenInApplication、ImageCompression 三端使用相同能力名；共享请求、Extension 菜单和主应用用例据此相互定位。主应用独有的模板管理不必在 Extension 创建空目录。只有内容已复杂的能力才展开多层。

`FileSystem/` 只收纳当前多个能力确实共用的命名与错误模型。`PasteboardWriter` 留在 CopyPath，ImageIO 留在 ImageCompression；不预建装满全系统接口的通用 Services/Utils 层。

## 现有目录到目标责任的映射

| 现有位置 | 目标位置 / 处理 |
|---|---|
| `ECMenu/App` + `ContextCommandComposition` | 生命周期继续在 App；实例装配归 ApplicationComposition；注册顺序与声明保留 |
| `Settings/StatusPage/StatusPage.swift` | Settings 保留外壳；通用、菜单配置、模板内容移动到相应 Feature 呈现；读系统和文件选择转明确操作边界 |
| `Settings/StatusPage/FileTemplate*` + `ECMenu/FileTemplates` | 合并在 FileTemplates 能力内，按领域/操作/存储/呈现拆开；控件身份与会话生命周期保持 |
| `ECMenuShared/FileTemplates/FileTemplate.swift` | 拆出共享 ID；完整模型和管理校验移主应用 FileTemplates Domain，菜单描述继续共享 |
| `ECMenu/MenuConfiguration` + `ApplicationIPCServer.menuSnapshot` | 配置能力的 Application/Persistence，IPC 注入快照读取闭包 |
| `ContextCommands/Features/<能力>` | `Features/<能力>`；先明确完成结果，再按独立职责拆文件 |
| `ContextCommandExecution.swift` | CommandRuntime，按注册/Invocation/Router 的复杂度拆文件；保留类型关系 |
| `ContextCommands/Presentation/Progress` | 状态/Reporter/Center 归 CommandRuntime/Progress；NSPanel 与行视图归 Feedback |
| `ContextCommands/FileNaming.swift`、`SystemError.swift` | FileSystem，共用定义保持单一来源 |
| Extension `ContextMenu` | 通用 Menu 与同级 Features；Controller 保留冻结动作与上下文，并明确 tag 生命周期和有界淘汰 |
| Shared `IPC` / `Rendering` / `Logging` | Contracts 与 Platform 区分，资源所有权保持原有单一边界 |

Xcode 使用文件系统同步组，目录变化仍须核对 target membership 和 `membershipExceptions`；尤其 Preview 与集成 Sender 只编译所需源码。[project.pbxproj](../../../../ECMenu.xcodeproj/project.pbxproj)、[预览边界](../../../Technical/PreviewTarget.md)。

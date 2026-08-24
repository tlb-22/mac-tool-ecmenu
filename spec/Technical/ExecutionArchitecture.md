# 进程、交付与权限边界

产品行为见[需求总述](../Requirements/Main.md)。本文只记录跨进程协议、信任和权限等无法由单个功能文件表达的约束；Finder API 语义集中在 [Finder 集成边界](FinderIntegration.md)。

## 进程职责

- **Finder Extension**解释 Finder 事件、构建菜单、冻结语义上下文，并从中准备各功能所需的最小类型化负载。它保持 App Sandbox，只读取菜单判定所需事实，不执行产品文件操作，也不呈现业务结果。
- **主应用**是配置真相源、命令执行端和反馈出口。它以普通非沙箱 macOS 进程执行文件系统、剪贴板、Launch Services、设置窗口和 Finder 反馈操作。
- **Shared**保存两个产品二进制必须一致的命令、全局控制契约与无场景跨 target 渲染原语，不保存 AppKit 菜单、平台副作用或主应用执行逻辑。

这种职责划分让 Finder 生命周期和权限限制停留在采集端，让未来性质不同的动作仍由同一个可控执行端承载。

## 主应用呈现与进程生命周期

### 项目设计

主应用采用单进程双呈现状态。命令服务器与进程同生命周期，不依赖配置会话存在：

- **配置会话打开态**（`configurationVisible`）已经打开唯一状态页，并把应用 activation policy 设为 `.regular`，使其出现在程序坞中。状态页被最小化时仍属于此状态。
- **配置会话关闭态**（`configurationHidden`）已经关闭状态页，并使用 `.accessory`，使进程继续接收和执行命令而不出现在程序坞中。

用户普通打开或重新打开应用会打开配置会话。点击状态页关闭按钮、在状态页按 `Command-W` 或选择 `Command-Q` 都只关闭配置会话；其中 `Command-Q` 是产品定义的配置会话关闭动作，不调用进程终止。再次打开应用复用同一进程和状态页。

activation policy 只由配置会话是否打开决定。最小化状态页不关闭配置会话。参数窗口、错误弹窗和进度窗口由命令执行边界按需呈现，但不能把配置会话关闭态提升为 `.regular`；无界面命令也不能激活应用。关闭配置会话不取消已经登记的命令或进度任务。

### 登录启动

#### 平台契约与证据边界

Xcode 26.6（17F113）附带的 macOS 26.5 SDK 与 Apple 官方文档定义了以下边界：

- [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) 表示当前主应用；登记它会让系统在用户后续登录时启动主应用，取消登记不终止当前进程。
- `SMAppService.Status` 区分未登记、已启用、需要用户批准和找不到服务；状态是系统事实，不是应用偏好值。
- CoreServices 将 `keyAELaunchedAsLogInItem` 定义为 `kAEOpenApplication` 的登录项启动标记；SDK 头文件没有完整描述该标记在事件参数中的容器形状。
- 为同一 Apple Event class/ID 登记自定义 handler 会接管该事件。当前应用没有文档窗口或 untitled-document 恢复语义，因此可以完整接管 `kAEOpenApplication`；未来加入文档类型或状态恢复时必须重新审视此边界。

项目在 macOS 26.6.1（25G76）的真实注销、登录中观察到，`SMAppService.mainApp` 由 loginwindow 通过 Shared File List 自动启动，并只向主应用发送一次 `kAEOpenApplication`；事件把 `keyAELaunchedAsLogInItem` 作为 `keyAEPropData` 参数的枚举值携带，而不是作为参数关键字。同期日志显示会话恢复应用数量为零，因此不能把该事件误判归因于第二次 reopen 或会话恢复。普通冷启动与运行中 reopen 则会复用唯一进程和状态页。

项目在同一系统版本中分别启用和关闭登录窗口的“重新打开窗口”选项进行验证：注销前处于 `configurationHidden` 的应用在重新登录后都不会打开 Status Page。配置窗口是否出现仍由收到的应用打开事件及其登录项标记决定。

#### 项目设计

`LoginItemController` 使用 `SMAppService.mainApp` 管理主应用自身的登录项，不新增 Helper、Launch Agent 或 XPC Service。登录项只是系统在后续登录时启动同一个主应用的策略，不建立第二种命令宿主：

- 开启设置调用 `register()`，关闭设置调用 `unregister()`；两者只改变后续登录启动登记，不启动或终止当前进程。
- `SMAppService.mainApp.status` 是界面的外部状态真相源。`.notRegistered` 映射为开关关闭；`.enabled` 映射为开关开启且不显示额外文字；`.requiresApproval` 映射为开关仍然开启和“未批准”。状态可能由用户在系统设置中改变，因此配置界面重新获得焦点时重新读取，而不以单独持久化的布尔值覆盖系统事实。
- `.notFound` 只表示本次状态查询没有找到服务：界面显示关闭，但不把它解释成永久不可操作。用户开启时仍调用 `register()`，再以调用结果和刷新后的系统状态为准；实际登记错误不能让界面假装成功。

应用读取首个 `kAEOpenApplication` Apple Event 的 `keyAEPropData` 枚举值；它等于 `keyAELaunchedAsLogInItem` 时进入 `configurationHidden`，只建立命令服务器，不创建或显示状态页，也不激活应用；其他值或缺少该参数时进入 `configurationVisible`。启动来源只决定本次进程的初始呈现，进程存活期间后续的普通 reopen 事件仍打开唯一状态页。实现不通过启动延时、当前激活状态或进程参数猜测来源。

应用完整接管标准 Open Application 与 Show Preferences Apple Event：前者决定初始呈现并处理后续普通打开，后者统一显示唯一状态页，避免空的 SwiftUI Settings Scene 形成第二条配置窗口路径。

### 恢复边界

主进程被强制退出、崩溃或注销后，命令服务器随之消失；Finder Extension 的进程和菜单缓存不代表执行端仍然存在。用户普通打开应用会立即建立新的命令宿主；“登录时打开”已经登记且获系统批准时，系统会在后续登录中自动建立后台命令宿主。该登录项不会在当前会话中监护或自动重启被终止的进程。

Finder Extension 的公开 URL 打开入口在当前验证环境中不能作为可靠恢复机制，平台观察见 [Finder 集成边界](FinderIntegration.md#extension-打开-url-与状态)。当前产品不提供进程被终止后的会话内自动恢复保证。

## 命令投递语义

Finder Extension 在菜单构建时为每个可见叶子准备一份不可变类型化命令；点击时建立一条定向连接并只发送对应命令一次。命令只携带该功能执行所需的绝对路径、非空选择或单一目标，不继续携带可表示无关 Finder 场景的通用上下文。命令通道是 one-way send：Extension 不等待主应用返回接管状态或业务执行结果，也不设置自动重试、交付超时、请求去重或提交状态查询。

### 单次命令时序

```text
Finder Extension                         主应用
       │                                   │
       │  1. 建立 App Group Unix socket     │
       ├──────────────────────────────────>│
       │                                   │
       │  2. Client 验证主应用身份           │
       │     Server 验证 Extension 身份      │
       │                                   │
       │  3. 认证就绪 ACK（空 frame）         │
       │<──────────────────────────────────┤
       │                                   │
       │  4. 命令 frame（8 字节长度 + JSON）  │
       ├──────────────────────────────────>│
       │                                   │
       │  5. 完整写入后关闭；无命令接管 ACK    │
       │                                   │
       │                     6. schema 检查与解码
       │                     7. 恢复类型化调用
       │                     8. 登记独立 Task
       │                     9. Handler 执行与反馈
```

连接建立后，客户端和主应用分别验证对端身份；主应用只有在验证 Extension 后才发送认证就绪 ACK。该 ACK 保证主应用取得动态对端身份前客户端不会关闭连接，只确认认证阶段完成，不携带命令接管状态或业务结果。连接建立、对端身份验证、认证就绪 ACK、编码或完整写入失败时，Extension 记录错误并播放一次系统默认错误提示音。完整写入成功只表示本次点对点发送完成；它不证明主应用已解码请求、恢复调用或执行业务。

主应用对通过运行态身份验证的命令依次检查 schema、解码信封并恢复已注册的类型化调用；不兼容 schema、无法解码的负载或未知命令只记录并丢弃，不回送应用层响应。恢复成功后由 Router 登记独立 Task，后续进度、取消和业务反馈均由主应用内部负责。

主应用未运行或瞬时通信失败时，本次点击结束，用户可在宿主恢复后再次点击。用户的每次点击是一个独立请求；产品不尝试在进程之间提供 exactly-once 交付。功能负载的编码形状发生不兼容变化时必须提升请求 schema，不依赖宽松解码猜测旧负载。

## 交付与并发

完整命令只通过 App Group 容器内经过双向身份验证的 Unix-domain socket 进入常驻主应用。每条连接使用八字节大端正文长度 framing；主应用先写入一个空的认证就绪 ACK frame，Extension 再写入一份 JSON 请求。命令连接此后不读取响应，菜单配置查询则继续读取配置快照；两者不共享命令接管 ACK、重试或去重语义。URL 不是第二条执行入口，也不属于当前命令可用性保证。

各请求独立执行，不使用跨功能的全局串行队列。只有具体功能出现真实的容量、顺序或共享资源约束时，才由该功能增加局部调度策略。

## 可选命令进度

### 平台契约与证据边界

Xcode 26.6（17F113）附带的 macOS 26.5 SDK 将 Foundation `Progress` 定义为工作量与取消状态的可观察模型，并提供按文件 URL 发布和跨进程订阅的机制（`NSProgress.h:18–33, 109–121, 210–231`）。文件类型 Progress 的工作单位是字节，文件数量由独立的 total/completed file-count 信息表达（`NSProgress.h:81–86, 197–208, 261–288`）。

上述发布契约只说明匹配文件 URL 的订阅者可以发现进度，没有承诺 Finder 会订阅任意应用发布的任务，也没有承诺采用 Finder 自身的复制进度界面。同期 Finder Sync SDK 的公开接口也没有登记第三方文件任务进度的入口。该结论来自公开 SDK 表面，不推断 Finder 私有实现。

同期 AppKit SDK 的 `NSProgressIndicator` 没有公开的填充颜色属性；已废弃的 `controlTint` 在 macOS 10.15 之后不再生效。项目在上述验证环境中观察到，标准进度条位于 nonactivating 面板时会随窗口非激活状态呈现为灰色。本产品不为进度自动激活主应用：面板弹出时保持灰色，只有用户主动使其成为 key window 后才使用系统强调色。轻量自绘进度槽用于稳定粗细、自适应宽度并保持这一焦点配色。

### 系统界面观察

项目于 2026-08-20 在 macOS 26.6.1（25G76）中人工观察 Finder“转换图像”快速操作的进度窗口，其内容将任务图标放在左侧，右侧依次显示操作名称、进度条与取消按钮、剩余时间；标题栏中关闭和最小化按钮呈可用外观，缩放按钮呈禁用外观。

该截图只记录特定系统版本的可见行为，不证明 Finder 内部窗口类型或布局实现，也不构成未来 macOS 版本的稳定 API 契约。

### 跨模块约束

产品不依赖 Finder 私有进度界面，由主应用拥有共享的 AppKit 任务窗口。进度是命令可选提供的确定整数能力；没有进度的命令不进入窗口，多个命令的进度展示也不改变各请求原有的并发关系。显示延迟、窗口关闭和多任务行为见[需求总述](../Requirements/Main.md#长时间命令进度)。

当前唯一提供进度的图片压缩命令同时支持项目边界取消。窗口中的取消只传递协作意图，由图片压缩在不会破坏单项输出的边界响应；它不替代 Router 对应用生命周期使用的 Swift Task cancellation。具体功能仍自行定义计数单位、安全取消边界和部分结果语义，通用执行层只负责登记任务、传递取消意图，并在任务结束时同步结束对应的进度生命周期。

任务行的名称和图标使用命令 descriptor 作为单一事实源，Finder 菜单、进度窗口和开发预览不分别维护副本。面向用户的产品名称以应用 Bundle 显示名称为单一事实源，进度窗口标题不再定义另一份名称。

## 界面预览边界

界面预览由独立的沙箱 macOS App target 承载。它在单独进程中复用生产 renderer 和共享契约，只在开发边界注入合成状态；产品主应用不包含预览分支，预览应用也不启动命令服务器、嵌入 Finder Extension 或参与产品归档。因此人工检查能够覆盖真实标题栏、AppKit 布局、图标和多任务状态，同时不改变正在运行的产品生命周期。

预览不是自动化 UI 测试。稳定 runtime 只解析预览 ID、验证声明唯一性并保活对应会话；每个 Case 在文件开头集中保存可调模拟参数，随后通过正常生产入口构造界面。设置页使用无副作用的呈现状态，压缩设置窗口绕过持久化 Prompt，进度任务只存在于预览进程内存。完整测试保证 Preview target 可编译并能从唯一注册表列出入口；可见效果仍由人工验收，详细入口见 [开发脚本](../../scripts/Main.md#界面预览)。

## 信任边界

### 平台契约与验证方式

官方契约：Xcode 26.6（17F113）附带的 macOS 26.5 SDK 为本地 Unix socket 定义 `LOCAL_PEERTOKEN`，返回连接对端的完整 `audit_token_t`。Security Framework 的 `SecTaskCreateWithAuditToken` 用该令牌表示对应运行任务；macOS 14.4 起公开的 [Lightweight Code Requirements](https://developer.apple.com/documentation/lightweightcoderequirements) API 通过 [`SecTaskValidateForRequirement`](https://developer.apple.com/documentation/lightweightcoderequirements/sectaskvalidateforrequirement%28task%3Arequirement%3A%29) 判断该任务的可执行代码是否满足类型化的 `ProcessCodeRequirement`。

项目实测：在 macOS 26.6.1（25G76）中，保持 App Sandbox 的 Finder Extension 可以用这一组合验证非沙箱主应用；主应用也可以对称验证 Extension。旧的 `SecCodeCopyGuestWithAttributes` 动态代码路径需要读取对端的磁盘代码，Extension 在开发期无权读取 `.derivedData` 中主应用的可执行文件时会返回 `EPERM`。项目不为开发目录添加临时文件例外，也不退化为只读取可伪造的 signing identifier 或 entitlement。

App 与 Extension 在同一构建配置中共同声明 Team-ID 风格 App Group，并只通过 `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` 定位组容器，不拼接用户目录。主应用在容器内拥有一个权限为当前用户读写的 Unix-domain socket。App Group 让保持 App Sandbox 的 Extension 可以连接非沙箱主应用，但不替代连接对端身份验证。

### 构建身份与配置隔离

项目固定使用以下成对身份：

| 配置 | 主应用 signing identifier | Finder Extension signing identifier | App Group |
|---|---|---|---|
| Release | `com.axiomace.ecmenu` | `com.axiomace.ecmenu.finderext` | `GVPW27HJZ5.ecmenu` |
| Debug | `com.axiomace.ecmenu.debug` | `com.axiomace.ecmenu.debug.finderext` | `GVPW27HJZ5.ecmenu.debug` |

Xcode build configuration 分别设置 `ECMENU_APPLICATION_BUNDLE_IDENTIFIER`、`ECMENU_FINDER_EXTENSION_BUNDLE_IDENTIFIER` 与 `ECMENU_APPLICATION_GROUP_IDENTIFIER`。前两项同时决定产品 bundle identifier 和运行态 signing identifier；三项还分别以 `ECMApplicationSigningIdentifier`、`ECMFinderExtensionSigningIdentifier` 与 `ECMApplicationGroupIdentifier` 注入两个产品的 `Info.plist`，App Group 同时注入各自 entitlement。运行时代码只读取当前二进制的注入值，不以源码条件编译或硬编码常量重新判断 Debug/Release；缺少或为空的身份配置属于构建错误，不能降级到另一配置。

非发布目标统一使用 `com.axiomace.ecmenu.test` 子树：主应用测试、Extension 测试、Preview 和 IPC helper 分别使用 `.main`、`.finderext`、`.preview` 与 `.ipcsender` 后缀。IPC helper 是刻意验证生产身份检查的唯一例外：其产品 bundle identifier 仍属于测试子树，但代码签名 identifier 由构建配置显式覆盖为对应的 Finder Extension identifier；它只存在于本地集成测试，不嵌入或交付到产品应用。

不同 bundle identifier 隔离标准偏好、登录项身份以及 Launch Services/PlugInKit 登记；不同 App Group 隔离组容器和其中固定叶名为 `ipc` 的 socket；菜单配置变更通知名从主应用 signing identifier 派生。因此 Debug 与 Release 不共享偏好、配置副本或 IPC，也不能互相通过身份验证。该隔离不负责仲裁 Finder 同时启用的 Extension 数量；若两者都启用仍可能出现重复菜单，开发和切换流程应保证同一时刻只启用需要测试或使用的一方。

### 项目设计

两端在 connected socket 上、读取或发送任何业务正文之前取得内核 audit token，并对由该 token 定位的运行任务执行以下双向约束：

- 主应用只接受当前构建配置注入的 Finder Extension signing identifier；Extension 只接受同一配置注入的主应用 signing identifier，具体配对见上表。
- 两端必须与验证方当前进程具有相同 Team identifier，且运行态验证兼容 Apple Development 与 Developer ID 签名类别；项目的 Personal Team 构建只使用 Apple Development。
- 目标进程必须处于“已签名且动态有效”状态；任一 API 求值失败或约束不匹配都关闭连接，不降级到 PID、进程路径、原始 `SecTask` 字段、正文声明或内置共享密钥。

命令请求与完整菜单配置请求/响应只在已验证的定向连接中传输，不广播完整路径或权威配置，也不保留可从二进制提取的 HMAC 密钥。该传输不声称加密，也不把同一 Team 的签名私钥泄露或系统级特权对手纳入其授权保证。

主应用仍使用 `DistributedNotificationCenter` 广播不携带正文的“菜单配置可能变化”信号。任意本机进程可以伪造该信号，但它只能促使 Extension 尝试一次已验证的定向拉取，不能直接改变菜单配置或触发命令。

命令请求版本错位时按 schema 丢弃。主应用与内嵌 Extension 始终作为同一应用版本成对交付；替换应用后 Finder 暂时保留旧 Extension 进程时，不兼容请求会失败而不会按旧形状猜测解码，重新加载 Extension 后恢复。当前协议不提供跨 schema 兼容、版本协商或两端独立升级能力。

## 文件访问权限

主应用关闭 App Sandbox，Finder Extension 保持 App Sandbox。动作链路不弹出逐目录 `NSOpenPanel`，也不保存 security-scoped bookmark；Extension 只采集菜单上下文和构造命令所需的瞬时事实，真正的文件操作由主应用完成。菜单阶段观察到的存在性和目录类型不跨进程成为永久保证，主应用执行时仍按功能要求重新验证外部状态。

“完全磁盘访问”放宽的是 TCC 保护，不授予 root 权限，也不能绕过 POSIX 权限、只读文件系统或 SIP。Finder Sync 的 `directoryURLs` 只定义 Extension 管理范围，同样不增加主应用权限。

Xcode 26.6 附带的 macOS 26.5 SDK 没有为普通应用提供通用的“完全磁盘访问”状态查询。尝试读取某个受保护路径只能证明该次访问成功或失败，不能排除 POSIX、ACL、SIP 或 Data Vault 等其他原因。因此状态页只提供中性的系统设置入口，不推断或存储二值授权状态；真实访问失败仍由具体命令分类。

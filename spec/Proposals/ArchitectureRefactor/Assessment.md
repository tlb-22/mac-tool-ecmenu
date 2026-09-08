# 结构评估

结论基于[当前功能地图](Current/Main.md)及对应源码。下面的“问题”指影响理解、修改和验证的结构成本；已经有意选择且成立的产品语义单独标明。

## 应保留的基础

| 当前基础 | 依据 | 重构约束 |
|---|---|---|
| Extension 冻结最小命令，主应用执行副作用 | [FinderContextMenuController](../../../ECMenuFinderExtension/ContextMenu/FinderContextMenuController.swift)、[ApplicationIPCServer](../../../ECMenu/IPC/ApplicationIPCServer.swift) | 继续以两个进程组织；菜单事实不能当作执行时授权或存在性保证 |
| 共享类型化路径、选择集、命令和稳定身份 | [Shared contracts](../../../ECMenuShared/ContextCommands/ContextCommandIdentity.swift)、[FinderContext](../../../ECMenuShared/ContextCommands/FinderContext.swift) | 保持发布过的 ID、wire 字段和持久化键；代码重命名不引发身份迁移 |
| 两端各有一个产品注册源 | [菜单 Composition](../../../ECMenuFinderExtension/ContextMenu/ContextMenuComposition.swift)、[执行 Composition](../../../ECMenu/ContextCommands/ContextCommandComposition.swift) | 保留对应关系与顺序测试，不增加共享的第三份注册清单 |
| 模板库 actor 是已提交索引的单一所有者 | [FileTemplateLibrary](../../../ECMenu/FileTemplates/FileTemplateLibrary.swift) | 保留“新副本先准备、索引后提交”的事务边界、独立迁移与有效空清单 |
| 不覆盖写入、批量部分成功、明确错误快照 | [NewFile](Current/NewFile.md)、[ImageCompression](Current/ImageCompression.md)、[SystemError](../../../ECMenu/ContextCommands/SystemError.swift) | 保留失败分类及已生成输出，不为目录调整重写系统算法 |
| 原生编辑会话与稳定控件身份 | [NameEditingSession](../../../ECMenu/Settings/StatusPage/FileTemplateNameEditingSession.swift)、[FileTemplatesPage](../../../ECMenu/Settings/StatusPage/FileTemplatesPage.swift) | 保留异步提交期间的焦点、选区、目标点击和列表身份；不能用刷新整个页面替代状态建模 |

## 值得调整的责任边界

### 1. 模板能力的呈现和应用协调分散在设置外壳

`ECMenu/FileTemplates/` 保存库与 Controller，模板页、文件操作会话、名称会话和文本控件在 `ECMenu/Settings/StatusPage/`，完整 `FileTemplate` 与本地化校验错误又编译在 Shared 中。[StatusPage](../../../ECMenu/Settings/StatusPage/StatusPage.swift)还直接协调选择文件和模板操作。

影响：修改一个模板交互，需要跨设置外壳、业务目录和共享目录寻找一组共同变化的代码；模板页的生命周期约束难以从目录看出。

目标：把模板领域模型、应用操作、持久化和模板页呈现放入同一能力目录；设置外壳保留导航与页面装配。Extension 只需的模板 ID 和菜单描述继续留在共享契约，完整管理模型回到主应用。复杂的原生编辑会话独立保留。

### 2. `execute → present` 的业务完成点并不统一

[CopyPathHandler](../../../ECMenu/ContextCommands/Features/CopyPath/CopyPathHandler.swift) 的 `execute` 返回路径计划，`present` 才调用 `NSPasteboard.clearContents/setString`。新建文件、可见性和图片压缩则在 `execute` 内产生主要业务效果。

这是[现有执行设计](../../Technical/Runtime/CommandExecution.md)允许的主线程输出方式，不是实现违约。其代价是：看到 Outcome 无法统一判断业务已经完成；剪贴板写入失败没有进入该 Outcome，执行测试也尚未覆盖这一决定成功的边界。

目标：用例可以调用 MainActor 系统适配器；在实际剪贴板写入后返回业务结果。反馈层负责告知与 Finder 结果定位，不再承担决定“复制是否成功”的写入。线程归属与业务责任分别表达。

### 3. 模板提交结果和操作报错之间需要更明确的类型

[FileTemplateLibrary.remove](../../../ECMenu/FileTemplates/FileTemplateLibrary.swift) 先提交索引，再清理文件；清理失败会抛错，但删除已经生效。Controller 在错误路径重读已提交清单。更换的旧副本清理失败则仅记日志。[模板技术边界](../../Technical/Features/NewFile.md#模板库持久化)明确这两种当前行为。

影响：单一 `throws` 无法直接说明“拒绝修改”还是“已提交但清理有问题”，调用端要额外读取事实才能正确显示。

目标：结果区分提交前失败、已提交、已提交且有清理问题；发布以已提交结果为依据，反馈保留删除与更换各自的产品策略。这个调整改变内部契约，不改变存储顺序。

### 4. 菜单快照的组装与失效提示缺少集中的应用责任

[MenuConfigurationController](../../../ECMenu/MenuConfiguration/MenuConfigurationController.swift)同时更新内存、写 UserDefaults 和发通知；[ApplicationIPCServer.menuSnapshot](../../../ECMenu/IPC/ApplicationIPCServer.swift)组装配置与模板投影；[AppDelegate](../../../ECMenu/App/AppDelegate.swift)把模板 Controller 的变更接到同一个通知。

影响：模板变更通知目前从设置 Controller 路径产生，未来新增非 UI 写入入口时容易遗漏发布；IPC 服务还理解模板库失败应如何影响菜单产品状态。

目标：能力内建立菜单快照提供者与变更发布边界。所有生产模板变更入口都从统一的应用操作返回提交结果，再触发失效提示；管理页加载/重试成功也保留提示，让不可用副本有机会恢复。IPC 只转送请求和响应。配置与模板仍各有自己的存储所有者，不强行合并成一份可变巨型状态。

### 5. 部分文件已经具备多个独立职责，但目录还没有表达

| 位置 | 当前共同容纳的职责 | 建议边界 |
|---|---|---|
| [VisibilityHandlers](../../../ECMenu/ContextCommands/Features/Visibility/VisibilityHandlers.swift) | 操作/计划/结果、系统写属性、错误文案、日志与反馈 | 能力内分规则/用例与反馈；hide/show 共用同一流水线 |
| [OpenInApplicationHandlers](../../../ECMenu/ContextCommands/Features/OpenInApplication/OpenInApplicationHandlers.swift) | 目标事实、计划、应用查找/启动、结果和文案 | 能力内分用例、Workspace 适配、反馈；两个固定应用保持共用泛型实现 |
| [ImageCompressionSettingsWindow](../../../ECMenu/ContextCommands/Features/ImageCompression/ImageCompressionSettingsWindow.swift) | 参数会话保活、continuation、持久化时机、窗口控件与格式化 | 参数会话协调与窗口呈现分开；Store 从设置领域模型文件移出 |
| [ContextCommandProgress](../../../ECMenu/ContextCommands/Presentation/Progress/ContextCommandProgress.swift) | 进度领域事实、执行能力接口、延迟/取消/显示协调 | 执行框架拥有状态和生命周期，通过渲染回调连接独立窗口 |
| [ContextMenuFeature](../../../ECMenuFinderExtension/ContextMenu/ContextMenuFeature.swift) 与 [FinderContextMenuController](../../../ECMenuFinderExtension/ContextMenu/FinderContextMenuController.swift) | 上下文语义、Feature/Action 描述与绑定、菜单构建、AppKit 绘制 | 保留 Feature 内聚；明确上下文读取、语义菜单、AppKit 渲染及动作保活 |

拆分理由是独立职责和不同变化来源；简单能力仍可用少量文件，目录不要求统一四层模板。

### 6. Shared 中的共享语义与平台实现需要区分

`ECMenuShared` 同时保存跨进程 payload、模板管理模型、socket/Security 实现和 AppKit 绘图；[AuthenticatedLocalSocket](../../../ECMenuShared/IPC/AuthenticatedLocalSocket.swift)还承担身份、握手、deadline/framing、资源与监听生命周期。

目标：物理区分 `Contracts` 和 `Platform`，把只由主应用使用的模板模型移回能力目录。socket 按独立责任拆文件，连接及监听资源仍有唯一所有者；不把同一 fd 生命周期拆给多个对象共同负责。Shared 暂时仍是参与多个 target 编译的源码目录，不宣称已获得 Swift module 的依赖隔离。

### 7. 应用级依赖的生命周期需要集中可见

[AppDelegate](../../../ECMenu/App/AppDelegate.swift)以 lazy 属性装配服务，[ContextCommandComposition](../../../ECMenu/ContextCommands/ContextCommandComposition.swift)静态拥有模板库及 Handler，Router 默认取全局进度中心，窗口/Prompt 也有自己的单例入口。

影响：启动、测试、预览与业务会话的依赖生命周期需要横跨静态入口才能确定；目录移动本身不能解决隐式共享。

目标：由一个应用 Composition 显式构造并持有进程级对象，向 Router、IPC、设置页注入窄接口/闭包。保留业务会话各自生命周期；不用 service locator，也不为每个纯函数引入协议。

## 独立于结构重构的行为决策

| 项目 | 当前事实 / 风险 | 本提案处理 |
|---|---|---|
| 配置同步的收敛保证 | 启动/监听恢复和收到通知时拉取；通知可能丢失，API 没有有限到达保证 | 结构重构保留现状并明确记录；如果产品要求菜单在规定时间内更新，另行设计非阻塞重新校验和验收时限 |
| 命令可靠投递 | 单向写出，不回传完成；未持久化命令，无自动重放 | 保留。需要完成回执、持久队列或去重属于跨进程协议与产品语义变更 |
| 配置损坏处理 | 菜单配置解码失败记录日志并使用 standard；模板索引损坏则显式失败 | 重构先保留这两个已实现策略；若调整用户反馈/恢复方式，单独确认产品行为，不混入类型搬迁 |
| 模板首次初始化中断 | 写目录或初始副本后，索引提交失败可能留下“已有根目录、缺失索引”；普通重试不能自动恢复初始化 | 明确记录并纳入失败验收；自动恢复属于独立的持久化恢复设计，不能以静默重建覆盖潜在数据 |
| 并发与取消 | 不同命令独立 Task；图片批内顺序；用户取消在单项完成边界生效 | 保留；没有性能测量支持新增全局队列/限流，也不承诺中断同步 ImageIO |
| 反馈窗口 | 错误使用 NSAlert 模态循环；参数和进度是独立会话 | 保留用户交互；引入反馈协调接口不等于改变窗口形态 |

目标目录与责任契约见 [Target](Target/Main.md)，实施顺序和回归边界见[迁移计划](Migration.md)。

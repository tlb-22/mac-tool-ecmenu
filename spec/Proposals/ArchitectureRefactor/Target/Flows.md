# 目标执行流与外部边界

**以下均为待实施设计。** 目标调整责任和内部契约，保持现有产品流程及系统 API。未单独重画的 F01、F09、F10、F12–F15 沿用当前外部行为，目录/依赖变化见[模块契约](Boundaries.md)；它们的 API 输入/输出仍以对应当前流程表为基线。

## T01 · 新建文件与复制路径的完整业务结果

```mermaid
sequenceDiagram
    autonumber
    box Finder Extension 进程
        participant E as 菜单 / 命令客户端
    end
    box ECMenu 主应用进程
        participant R as IPC / CommandRuntime
        participant U as 功能用例
        participant A as 读写适配器
        participant P as 反馈策略
    end
    participant S as macOS / 文件系统
    E->>R: 类型化请求 · 已认证单向 socket
    R->>U: 解码后的命令 + 执行能力
    U->>A: 取得当前事实 / 模板内容
    A->>S: 文件读取 API
    S-->>A: 值或明确失败
    A-->>U: 不可变事实 / 内容
    U->>U: 纯规则形成计划
    U->>A: 执行主要业务写入
    alt 新建文件
        A->>S: Data.write(.withoutOverwriting)
    else 复制路径
        A->>S: MainActor · NSPasteboard.clearContents / setString
    end
    S-->>A: 写入结果
    A-->>U: Created / Copied / 类型化失败
    U-->>R: 完整业务结果
    R->>P: 结果与本地任务 ID
    P->>S: 需要时 NSAlert / beep / Finder 结果选择
```

| 目标模块 | 输入 → 输出 | 外部 API 与失败边界 |
|---|---|---|
| 新建用例 / 纯命名规则 | 目录 + 模板 ID → 创建结果 | 自身依赖模板读取/排他写入接口；纯候选命名无外部 I/O |
| 模板读取适配器 | ID → 元数据 + Data / 模板失败 | 同一 FileTemplateLibrary actor 的 `open/fstat/FileHandle`；取得值后不再查询模板 |
| 排他写入适配器 | Data + 首选 URL → 创建 URL / 目标失败 | `Data.write(.withoutOverwriting)`，只在已存在时继续候选 |
| 复制用例 / 计划 | 非空路径 + 存在事实 → 完整复制结果 | 规则无 I/O；事实读取使用 `lstat`；不遗漏真正写剪贴板的结果 |
| PasteboardWriter | 多行 String → 成功 / 写失败 | MainActor `clearContents` / `setString(.string)`；保留两步非事务语义 |
| 反馈策略 | 已完成的业务结果 → 用户告知/结果定位 | NSAlert、NSSound、OSLog；新文件另调用 `selectFile`，定位失败不把创建成功改写为失败 |

对应当前 [F07](../Current/NewFile.md)、[F08](../Current/FileCommands.md)。新建文件大体保留，复制路径把主要输出从 `present` 纳入用例，避免为了“后台执行”而错误移动 AppKit 调用的线程。

## T02 · 配置变更与模板可用性驱动菜单发布

```mermaid
sequenceDiagram
    autonumber
    box ECMenu 主应用进程
        participant V as 设置呈现 / 操作会话
        participant U as 配置或模板应用操作
        participant S as 对应存储所有者
        participant P as 菜单变更发布 / 快照提供者
        participant I as IPC 请求适配
    end
    participant N as macOS 通知服务
    box Finder Extension 进程
        participant E as Replica / 缓存
    end
    V->>U: 类型化变更意图 / 模板加载或重试
    U->>S: 更新配置 / 模板操作或读取
    S-->>U: 更新、提交或读取结果
    U-->>V: 新状态或失败；保留编辑语义
    opt 配置更新、模板提交或管理页加载重试成功
        U->>P: 菜单事实变更或可用性重新确认
        P->>N: DistributedNotificationCenter：无正文提示
        N-->>E: 可能到达的失效提示
    end
    E->>I: 启动或提示后，认证 socket 查询
    I->>P: currentMenuSnapshot()
    P->>S: 读取当前开关与模板菜单投影
    S-->>P: 各自的已提交事实 / 模板不可用
    P-->>I: 完整 MenuConfigurationSnapshot
    I-->>E: JSON / framed response
    E->>E: 校验、整体应用、更新 UserDefaults 副本
```

| 目标模块 | 输入 → 输出 | 外部 API 与失败边界 |
|---|---|---|
| 配置应用操作 | Bool / Feature 可见性 → 有效配置 | 通过 UserDefaults store 更新；set 无同步持久化回执 |
| 模板应用操作 | 管理意图 / 加载重试 → 提交或读取结果 | 经单一 actor 完成文件和索引操作；已提交的清理问题及管理页成功加载/重试都触发提示 |
| 快照提供者 | 当前事实读取边界 → 快照 | 无直接 UI/socket 调用；模板不可用仍保留当前开关，清单为空有独立语义 |
| 变更发布者 | 已改变菜单事实 / 可用性重新确认 → 失效提示 | `DistributedNotificationCenter.post...`；提示可能丢失，不传送配置正文 |
| IPC 适配 | 查询请求 → 完整快照响应 | 同一已认证 socket/JSON/framing；不直接理解模板库错误 |
| Replica | 有效快照 → 下次菜单使用的副本 | `UserDefaults` 缓存；拉取中的新提示使当前响应失效，再拉一次；失败保留最后有效副本 |

对应当前 [F03/F04/F06](../Current/ConfigurationAndTemplates.md)与[副本流程](../Current/MenuAndIPC.md)。提供者可以分成投影纯函数与应用读取协调，按复杂度决定；不保存一份冗余的全局菜单真相。

发布包含成功只读重试，使之前缓存 `.unavailable` 的 Extension 获得重新查询机会。首次读取若完成初始化/迁移提交，由模板应用边界发布；普通查询已缓存清单不发布。IPC 开始监听时仍独立发送提示。完整发布输入见[模块契约](Boundaries.md)。

## T03 · 模板交互、提交与编辑焦点

```mermaid
flowchart TB
    subgraph presentation[主应用 · 模板呈现]
        intent[文件操作 / 名称编辑意图]
        session[操作与编辑会话<br/>保留控件、输入、待交接目标]
        choose[导入或更换时选择文件<br/>NSOpenPanel]
        ui[显示已提交列表<br/>成功交接焦点 / 失败保留输入]
    end
    subgraph application[主应用 · 模板应用操作]
        operation[执行类型化管理请求]
        decision{提交结果}
        publish[发布已提交快照<br/>触发菜单失效提示]
    end
    subgraph persistence[主应用 · 模板库与平台边界]
        prepare[验证已选择的普通文件<br/>open / fstat]
        content[准备新的独立副本<br/>FileHandle / Data.write]
        commit[提交 index.json<br/>Data.write atomic]
        cleanup[需要时清理旧副本<br/>FileManager.removeItem]
        discard[准备过新副本时尽力清理它<br/>保留旧索引与原提交错误]
    end
    intent --> session
    session -->|导入 / 更换| choose
    choose -->|已选择 URL| operation
    choose -->|用户取消| ui
    session -->|改名 / 删除| operation
    operation --> prepare --> content --> commit --> cleanup
    cleanup --> decision
    operation -->|改名或删除：直接提交索引| commit
    prepare -->|失败| decision
    content -->|失败| decision
    commit -->|失败| discard --> decision
    decision -->|提交前失败 / 取消| ui
    decision -->|已提交，含可能清理问题| publish --> ui
```

图中只有导入/更换需要准备新副本；改名只更新索引，删除提交索引后清理。普通“打开模板”经读取边界得到当前 URL，再通过 Workspace 打开，沿用 F06，不产生索引提交。

提交失败后的新副本清理，与提交成功后的旧副本清理分开；前者清理失败只写日志，保留原提交错误和旧清单。成功提交的清理问题则进入已提交结果。

| 目标模块 | 输入 → 输出 | 外部 API 与失败边界 |
|---|---|---|
| 呈现/编辑会话 | 控件事件、草稿 → 提交意图/交接请求 | NSTextField、共享 field editor、SwiftUI；保留原生重入和一次提交期间最后目标点击规则 |
| 参数/文件选择适配 | 导入/更换意图 → URL? | NSOpenPanel；nil 表示用户取消，不制造存储错误 |
| 模板应用操作 | 有效意图 → 提交结果 | 注入库操作与发布闭包；自身不持有另一份索引，不直接操作控件 |
| 持久化 actor | 文件/元数据意图 → 权威清单或失败 | 当前 FileManager、Darwin、FileHandle、Data API；区分提交前与提交后清理结果，保留独立 schema 迁移 |
| 反馈/发布 | 提交状态、维护问题 → 列表、错误反馈、失效提示 | 列表/原生焦点 API、NSAlert/日志、DistributedNotificationCenter；更换和删除保留各自既有清理反馈策略 |

## T04 · 图片参数与处理协作

```mermaid
sequenceDiagram
    autonumber
    box ECMenu 主应用进程
        participant U as 压缩用例
        participant Q as 参数会话协调
        participant V as 参数窗口
        participant A as 设置 / 图像 / 输出适配器
        participant P as 进度能力
    end
    U->>Q: 请求本批次参数
    Q->>A: UserDefaults load
    A-->>Q: 上次确认的有效设置
    Q->>V: 显示独立窗口并等待
    V-->>Q: 有效设置或取消
    opt 用户确认
        Q->>A: UserDefaults save
    end
    Q-->>U: 设置快照或取消
    opt 已确认设置
        U->>U: 纯规则生成排序与日期计划
        U->>P: begin(total)
        loop 按项执行，开始前检查取消意图
            U->>A: ImageIO 属性 → 纯尺寸规则 → 编码 → 写入 → 日期
            A-->>U: 单项结果，保留已生成输出
            U->>P: advance()
        end
        U-->>U: 汇总完整批量报告
    end
```

| 目标模块 | 输入 → 输出 | 外部 API 与失败边界 |
|---|---|---|
| 参数会话 | 本次输入快照 → Settings? | 以 continuation/取消处理连接窗口和等待者；Store 保存发生在确认后 |
| 窗口/表单 | 初始值、用户输入 → 有效设置/取消 | AppKit 控件、Formatter、NSWindow；不自行读写 UserDefaults |
| 设置 store | 键值 → 有效设置；设置 → 偏好更新 | UserDefaults；与领域设置定义分文件，无同步落盘回执 |
| 纯计划/尺寸规则 | URL 列表、设置、图像属性事实、基准时间 → 不可变计划 | 无文件 I/O；保留当前排序、视觉方向、目标尺寸和日期规则 |
| 图像/文件适配 | 单项计划 → 输出与失败事实 | ImageIO、CoreGraphics、FileHandle、Data.withoutOverwriting、setAttributes；日期失败保留输出 |
| 进度能力 / 反馈 | 批次进度与完整报告 → 可见快照/结果定位 | Center 接收事实，独立 NSPanel 渲染；完成后 Finder 选择与汇总反馈沿用 F11/F12 |

此目标保留批间并发、批内顺序、用户取消的安全边界和不同窗口独立输入。窗口任务保活与持久化时机属于参数会话，ImageIO 转换器只处理单图系统边界。

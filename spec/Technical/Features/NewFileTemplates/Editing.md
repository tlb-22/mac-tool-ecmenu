# 名称编辑与交互会话

名称编辑由模板能力的 Presentation 管理原生输入、草稿和焦点；Application 协调提交，Library actor 从当前记录更新单字段。产品交互规则见[文件模板页面](../../../Requirements/StatusPage.md#文件模板)，文件操作流程见[执行流](Flows.md#导入更换与删除)。

## 单字段提交与焦点交接

```mermaid
sequenceDiagram
    autonumber
    box ECMenu 主应用进程
        participant F as 原生字段与 field editor
        participant E as 编辑会话与草稿
        participant C as Controller 与 Operations
        participant L as Library 与名称规则
        participant S as 文件存储 Storage
    end
    F->>E: E01 输入、Return、失焦或另一个字段请求
    E->>F: E02 结束输入法标记，取得最新文字
    E->>F: 暂停当前字段输入
    E->>E: Draft.commit；并发请求共享同一提交 Task
    alt 值已改变
        E->>C: 模板 ID、字段、输入值
        C->>L: updateName(ID, field, value)
        L->>L: 从当前记录修改单字段并验证
        alt 输入有效
            L->>S: P04 原子提交完整索引
            alt 提交成功
                L->>L: 替换 records
                L-->>C: committed，带权威清单
                C->>C: Operations 发布；Controller 应用 ready
                C-->>E: 保存完成
            else 提交失败
                L-->>C: 原存储错误
                C-->>E: 保持 ready；返回保存失败
            end
        else 输入无效
            L-->>C: 名称验证错误
            C-->>E: 返回失败，不写索引
        end
    else 值未改变
        E->>E: 完成草稿，不调用保存
    end
    alt 草稿提交成功
        E->>E: 先更新 active；最后一次目标决定交接
        E->>F: E02/E03 结束旧字段或激活目标字段
    else 草稿提交失败
        E->>F: E02 恢复原字段输入与焦点
        E->>E: 保留草稿和错误，等待修改重试
    end
```

图中的 `Controller 与 Operations` 是呈现提交入口和应用操作的连续交接，详细职责见[模块映射](Flows.md#导入更换与删除)。只有 Library 的 `updateName` 从权威记录读取另一个字段；读取、构造有效模板和提交之间没有 actor 异步挂起点。名称修改保持模板 ID、文件引用、内部文件名和顺序，规则允许重名。

编辑会话接收保存期间的新目标，最后一次请求覆盖此前目标；这些请求共享当前草稿的同一次提交，过期请求不再交接焦点。成功时先修改唯一 active 状态，再结束旧控件，避免旧控件同步产生的失焦通知误清除新目标。失败时原控件继续接收输入，Controller 不切换 loading、不重新读取或重复发布原快照。

## 模块与状态所有权

| 模块 / 入口 | 输入 → 输出；所有权 | 外部边界 |
|---|---|---|
| [NameTextField / NativeField](../../../../ECMenu/NewFileTemplates/Presentation/FileTemplateNameTextField.swift) | 模板 ID + 字段、会话授权与 AppKit 事件 → 控件文字/可编辑性、提交/交接意图 | E01–E03；控件适配不访问模板存储 |
| [NameEditingSession](../../../../ECMenu/NewFileTemplates/Presentation/FileTemplateNameEditingSession.swift) | 原生控件协议、保存闭包和目标请求 → Bool 交接结果 | 无直接 AppKit/文件 I/O；唯一 active 持有草稿和控件，transition 持有最后请求与 Task |
| [NameDraft](../../../../ECMenu/NewFileTemplates/Presentation/FileTemplateNameDraft.swift) | 原始值、输入和保存闭包 → 保存结果、错误文字 | 无外部 I/O；拥有输入值和 idle/saving/saved 状态，重复提交共享 Task |
| [NameField / FileTemplate](../../../../ECMenu/NewFileTemplates/Domain/FileTemplateNameField.swift) | 当前模板、待修改字段和值 → 有效模板或验证错误 | 纯规则，无外部 I/O |
| [Library.updateName](../../../../ECMenu/NewFileTemplates/Persistence/FileTemplateLibrary.swift) | ID、字段和值 → 已提交清单或提交前失败 | 通过 Storage 使用 [P04 索引提交](Persistence.md#文件-api-与完成点) |
| [PageActions](../../../../ECMenu/NewFileTemplates/Presentation/FileTemplatePageActions.swift) | 文件操作意图、编辑会话 → 先完成名称再执行 | 无直接 I/O；phase 在等待名称、执行文件操作之间转移，切页不释放占用 |
| 设置外壳与 [NewFileTemplateSettingsPage](../../../../ECMenu/NewFileTemplates/Presentation/NewFileTemplateSettingsPage.swift) | 页面切换、后台通知、视图消失 → 请求完成编辑或更新导航 | E04；窗口会话持有编辑和文件操作对象，页面内容接收注入回调 |

草稿只拥有一个字段，不能保存整行旧副本覆盖其他最近提交的值。控件身份由模板 ID + 字段标识；同名模板不能共享一次编辑。名称输入和操作占用根据当前会话读取，不仅依赖下一轮 SwiftUI 属性更新。

## 入口、取消与后续操作

| 用户入口 | 提交与交接规则 |
|---|---|
| Return、失焦、背景点击 | 请求完成当前草稿；背景只接收未命中前景控件的点击，失败保留原草稿 |
| 点击另一字段、保存期间改变目标 | 保存完成后进入最后一次请求的字段；失败不进入后续目标 |
| Tab / Shift-Tab | 成功后使用窗口 key-view 导航，失败不移动 |
| Escape | 无交接任务时取消草稿并恢复原值；已有交接任务时忽略，不撤回正在保存的操作 |
| 点击另一设置分类 | 等待 `finishEditing()` 成功后才切页，失败停留原页 |
| 页面消失 / 应用失去 active | 发起结束编辑任务；它是提交触发，不是同步阻止系统切换的回执 |
| 导入、打开、更换、删除 | PageActions 先完成名称；失败阻止文件操作，成功后占用持续至操作结束，包括文件选择器等待 |

选择器取消正常释放占用，不回滚先前已完成的名称修改。短操作进度、名称只读与操作锁分别建模；视图移除时取消延迟指示器，不取消库提交。行为验收仍以[页面需求](../../../Requirements/StatusPage.md#文件模板)为准。

## 原生 API 输入输出

| 编号 / API | 输入 → 事件或结果 | 项目消费方式与约束 |
|---|---|---|
| **E01 控件事件**：`NSTextFieldDelegate` begin/change/end、`doCommandBy`，`mouseDown`、`becomeFirstResponder` | AppKit 原生编辑事件、选择器命令 → Coordinator / NativeField 回调 | 转换为会话意图；用户输入、程序化恢复和原生重入共享控件身份，不能把所有 end 通知都解释为用户离开 |
| **E02 文本与焦点**：`currentEditor()`、`NSTextView.hasMarkedText/unmarkText`、`selectText`、`setSelectedRange`、`NSWindow.makeFirstResponder` | 当前窗口 field editor、文字和选区 → 最新文本、焦点/选区状态 | MainActor；提交前结束标记并读最新文字，恢复时保留交接状态。`selectText` 可能产生同步原生通知，见下方项目观察 |
| **E03 键盘导航**：`selectKeyView(following:/preceding:)` | 当前控件和前后方向 → 窗口的 key-view 选择 | 只在保存成功后触发，不把导航请求视为存储成功回执 |
| **E04 页面生命周期**：`NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)`、SwiftUI `onDisappear` | 应用 inactive / 页面消失 → 异步完成编辑请求 | 请求在 MainActor 会话中协调；应用/窗口变化本身不等待索引提交 |

系统 field editor 的共享模型由 [Apple Cocoa Text Architecture Guide](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextEditing/TextEditing.html)说明。具体事件到达顺序仍需按项目使用方式验证，不能仅从共享模型推导全部焦点行为。

## 原生焦点证据与验收

项目观察（2026-09-08，macOS 26.6.2、Xcode 26.6）：对已经编辑的 `NSTextField` 调用 `selectText` 恢复选择时，可能同步产生结束编辑通知。因此程序化恢复期间仍属于当前交接，不能将该通知再次解释为用户离开字段。这是特定系统上的项目验证结果，不是所有 macOS 版本的通知顺序保证。

[会话测试](../../../../Tests/ECMenuTests/NewFileTemplates/Presentation/FileTemplateNameEditingSessionTests.swift)覆盖最后目标、同步重入、准备提交时的最新文字、失败恢复与取消；[草稿测试](../../../../Tests/ECMenuTests/NewFileTemplates/Presentation/FileTemplateNameDraftTests.swift)覆盖未变值不写和重复提交一次；[单字段更新测试](../../../../Tests/ECMenuTests/NewFileTemplates/Presentation/FileTemplateNameUpdateTests.swift)覆盖另一字段最新值和按 ID 更新；[隐藏窗口中的原生页面测试](../../../../Tests/ECMenuTests/NewFileTemplates/Presentation/NewFileTemplateSettingsPageTests.swift)覆盖控件身份、鼠标/键盘焦点、跨页面操作占用、背景点击和失败阻止文件操作。测试宿主的能力限制见[界面预览目标](../../PreviewTarget.md)。

2026-09-08 当前结构完整 231 项测试通过，包含上述原生控件、异步交接、提交结果与页面会话测试，详见[验证记录](../../Architecture/Verification.md)。隐藏窗口自动化不等于真实输入法与所有窗口场景的实机验收。

实机复核应在打开的文件模板页使用真实输入法，连续验证“输入中切字段、Return/Tab/Shift-Tab、保存期间再次点另一字段、保存失败继续修正、切分类和切前台应用、名称尚未完成时点文件操作”。观察应同时记录最终持久化值、原生焦点/选区和后续操作是否发生；仅看到正确文本不足以证明焦点或任务生命周期正确。

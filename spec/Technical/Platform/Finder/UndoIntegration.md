# Finder 撤销集成边界

本文件记录 Finder 原生撤销与扩展命令之间的公开能力边界。候选产品范围与实施步骤见[命令撤销与重做提案](../../../Proposals/CommandUndo.md)，当前执行职责见[命令执行](../../Runtime/CommandExecution.md)。

## 证据范围

2026-09-05 核对 Apple 官方文档，以及本机 Xcode 26.6（17F113）附带的 macOS 26.5 SDK；本机系统为 macOS 26.6.1（25G76），Finder 为 26.4。

本次完成公开接口与项目源码审阅，没有执行 Finder 文件操作或原生撤销实验。因此，以下接口范围属于文档与 SDK 证据；间接文件操作是否进入 Finder 历史仍属于待验证假设。公开接口中没有某个入口，不等于证明系统内部不存在该能力。

## 公开契约

### Finder Sync 与 UndoManager

Apple 的 [Finder Sync 指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html) 说明每个扩展实例运行在独立进程中，公开定制范围包括目录观察、徽标、上下文菜单和工具栏入口。

macOS 26.5 SDK 的 `FinderSync.h` 声明了 `FIFinderSyncController`、`FIMenuKind` 和 `FIFinderSync` 协议的完整接口。公开菜单种类是项目、目录背景、侧边栏和工具栏；没有编辑 Finder 菜单栏、获取 Finder 的 `UndoManager`、注册自定义撤销条目、枚举原生历史或接收原生 undo/redo 回调的接口。`FIFinderSync` 基类是 `NSObject`，不是 Finder 窗口的 responder。

Apple 的 [AppKit 撤销架构](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UndoArchitecture/Articles/AppKitUndo.html) 将撤销管理器选择定义在应用自身的 responder chain 中：undo/redo 从 first responder 向上寻找适用的管理器。

**推断**：在 ECMenu 主应用或 Extension 中调用 `UndoManager.registerUndo` 只能建立该进程拥有的历史；公开 Finder Sync 契约没有把它接入 Finder 响应链的桥梁。为扩展上下文菜单设置 `keyEquivalent`，同样不能据此承诺菜单关闭后 Finder 的标准 ⌘Z 会路由到扩展。

### Finder 代为执行文件操作

本机 `/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.sdef` 的 Standard Suite 声明 `delete`、`duplicate`、`make` 和 `move`，没有撤销、重做或历史注册命令。字典声明只能证明脚本可请求这些操作，不能证明每种操作的对象类型都可创建，也不能证明操作会形成原生撤销条目。

Apple 的 [AppleScript Fundamentals](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/conceptual/ASLR_fundamentals.html) 以 Finder `duplicate` 说明目标应用处理脚本命令的机制。真实应用采用该路线时，还需处理 [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)、[用途说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)及用户自动化授权；权限拒绝属于执行失败。

Apple 的 [NSWorkspace.recycle](https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:completionhandler:)) 与 [NSWorkspace.duplicate](https://developer.apple.com/documentation/appkit/nsworkspace/duplicate(_:completionhandler:))，以及 SDK `NSWorkspace.h:83–90`，描述了文件操作、完成结果映射和可能出现的系统 UI；没有承诺调用会注册到 Finder 的撤销栈。

**推断**：通过 Apple Events 让 Finder 自己完成复制或移动，是值得按具体操作验证的间接路径。即使某种操作在某版本可以原生撤销，也只证明 Finder 自己执行的那一步；不能推广为任意 ECMenu 副作用都能加入同一个自定义撤销组。

例如，把提前编码好的 JPG 交给 Finder 复制到目标目录，可能把待撤销对象转化为 Finder 的复制操作；它仍需验证批次分组、重做对源文件保留的要求、命名冲突和中途失败。该路径也不能直接表达隐藏属性恢复或外部应用操作。

### 快捷键监控

Apple 的 [Monitoring Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) 明确区分：全局 `NSEvent` monitor 只能观察其他应用事件，不能修改或阻止投递；局部 monitor 只能处理本应用的事件。

[CGEventTapCallBack](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback) 允许 active filter 返回空值删除事件，但 [tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) 受到系统事件访问权限约束，创建可能失败。

**推断**：在全局 monitor 中执行 ECMenu 撤销，原始 ⌘Z 仍可能同时触发 Finder 撤销。能抑制事件的其他输入机制也只解决按键路由，不能补出原生历史的读取、分组与跨应用顺序契约。

例：ECMenu 新建文件 A，随后用户在 Finder 中移动文件 B。只知道自身历史的 ECMenu 无法仅凭栈非空就判断下次 ⌘Z 应撤销 A 还是 B。观察文件系统变化也无法恢复用户意图、Finder 分组和当前 redo 分支；重命名文本框等输入焦点还具有自己的撤销上下文。

### App Intents

[UndoableIntent](https://developer.apple.com/documentation/appintents/undoableintent) 及其 [undoManager](https://developer.apple.com/documentation/appintents/undoableintent/undomanager) 将撤销连接到实现方应用或 app extension 的状态与界面。macOS 26.5 SDK 声明该协议从 macOS 26.0 可用，管理器可以为空。该契约没有提供 Finder 原生历史的接入入口。

## 项目判断

通过当前公开契约，无法把任意 ECMenu 命令可靠注册到 Finder 原生撤销历史。自有历史可以提供 ECMenu 命令的撤销与重做，但其所有权和顺序范围必须明确限定为 ECMenu。

Finder 代执行路线需要受限实验后才可纳入某个具体功能的设计；采用时必须记录验证系统版本、文件操作类型、分组和重做行为。以原生 ⌘Z 混合撤销所有命令为硬性验收条件时，当前证据不足以进入正式实现。

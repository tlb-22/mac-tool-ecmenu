# 应用运行生命周期

用户可见行为见[应用生命周期需求](../../Requirements/ApplicationLifecycle.md)。本文件记录主应用如何以一个进程同时承担配置界面和后台命令宿主。

## 呈现状态

命令服务器与主应用进程同生命周期，不依赖配置会话存在。以下名称只描述两种配置会话状态，不对应额外的源码状态类型：

- **配置会话打开**：唯一状态页正在显示，并使用 `.regular` activation policy。
- **配置会话关闭**：状态页没有显示，并使用 `.accessory` activation policy；窗口控制器仍可保留同一个窗口供下次打开复用。

activation policy 只由配置会话决定。最小化状态页不关闭会话；参数、错误和进度等业务窗口也不改变配置会话状态。普通打开、reopen 与 Show Preferences 事件都进入同一条显示状态页的路径，不创建第二个命令宿主或第二个配置窗口。

生命周期测试替换窗口和 activation policy 的系统副作用，直接执行应用事件处理路径，覆盖登录与普通打开、重复打开、最小化后重开、关闭状态页、`Command-Q` 与业务窗口并存，以及平台拒绝切换策略。窗口事实仍由 AppKit 持有，应用不维护第二份可见或最小化状态。真实登录来源和系统窗口恢复行为仍以注销、登录验收为证据。

## 登录启动

[`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) 管理主应用自身的登录项，不引入 Helper、Launch Agent 或 XPC Service。登记与取消登记只影响后续登录，不启动或终止当前进程。

`SMAppService.mainApp.status` 是登录项状态的外部真相源：`.notRegistered`、`.enabled` 与 `.requiresApproval` 分别映射为关闭、已开启和等待批准；界面重新 active 时重新读取。`.notFound` 只表示本次查询未找到服务，用户仍可尝试登记，最终以登记结果和刷新后的系统状态为准。

Xcode 26.6（17F113）附带的 macOS 26.5 SDK 将 `keyAELaunchedAsLogInItem` 定义为 `kAEOpenApplication` 的登录项启动标记。项目于 macOS 26.6.1（25G76）的真实注销、登录中观察到，loginwindow 只发送一次 Open Application 事件，并把该标记作为 `keyAEPropData` 的枚举值携带。无论登录窗口是否选择重新打开窗口，注销前隐藏的配置会话都没有被会话恢复重新显示。

应用完整接管标准 Open Application 与 Show Preferences 事件，避免 SwiftUI Settings Scene 形成第二条配置窗口路径。首个 Open Application 事件携带登录项标记时关闭配置会话，否则打开配置会话；进程存活期间的后续普通 reopen 和 Show Preferences 始终显示唯一状态页。启动来源不通过延时、激活状态或进程参数猜测。应用当前没有文档窗口或 untitled-document 恢复语义；未来加入这些能力时必须重新评估完整接管事件的边界。

## 恢复边界

主进程结束后命令服务器随之消失；Finder Extension 仍在运行或仍能显示菜单，不代表执行端存在。`SMAppService` 只负责后续登录启动，不在当前会话监护或重启进程。

主进程仍然运行时，IPC 初始化失败或监听终止由同一个应用侧所有者记录。用户普通打开、重新打开或显示设置时尝试恢复监听；启动成功后通知 Extension 再次拉取配置。监听的资源释放、可恢复错误与传输等待期限见 [IPC](IPC.md#等待与监听恢复)。

Finder Extension 的公开 URL 打开入口在当前验证环境中不能可靠冷启动主应用，平台证据见 [Extension 生命周期](../Platform/Finder/ExtensionLifecycle.md)。因此当前会话中的恢复入口是用户普通打开应用，不另建隐藏的自动恢复通道。

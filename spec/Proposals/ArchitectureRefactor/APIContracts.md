# API 证据与结果含义

各流程邻接表列出具体模块的输入、输出和调用；本页集中说明会影响架构判断的外部契约。以下为 2026-09-08 查询的 Apple 官方文档与本地 SDK 声明，不是本轮运行实测。

## 如何解释输入与输出

- 输入按实际进入系统边界的值描述，例如 URL、Data、bundle ID、socket descriptor；内部命令名不是操作系统 API。
- 输出同时区分 SDK 返回值和项目如何消费它。例如 `NSWorkspace.open` 返回的应用对象当前可能被忽略，项目只检查 Error。
- `Void` 不代表没有副作用，也不代表用户已经看到结果。无回执的 API 不应被画成已确认的业务成功。
- UI 呈现、主线程约束、持久化写入和进程边界分别标注；某个调用写在 MainActor 上，不自动意味着 Apple 要求它只能从主线程调用。

## 会改变设计判断的契约

| API 边界 | 输入 → API 输出 | 对流程的约束与证据 |
|---|---|---|
| Finder 上下文 | 菜单回调时读取 → `URL?` / `[URL]?` | `targetedURL` 与 `selectedItemURLs` 仅在菜单回调或其动作期间提供有效值，范围外可为 nil。菜单上下文需要在有效入口解释；项目进一步冻结动作输入。[targetedURL](https://developer.apple.com/documentation/findersync/fifindersynccontroller/targetedurl%28%29)、[selectedItemURLs](https://developer.apple.com/documentation/findersync/fifindersynccontroller/selecteditemurls%28%29) |
| Finder 管理范围 | `Set<URL>` → Extension 观察范围 | `directoryURLs` 应在 Extension 启动时设置；这是管理范围，不是写入授权。[directoryURLs](https://developer.apple.com/documentation/findersync/fifindersynccontroller/directoryurls)、[项目权限边界](../../Technical/Platform/FileAccess.md) |
| 偏好读写 | 键/可保存值 → 本地查询值，set 为 Void | UserDefaults 立即更新进程内值，异步写盘。配置图中的“保存偏好”不能解释为同步落盘确认。[UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults) |
| 分布式变更提示 | 通知名，无业务正文 → 观察者回调 | 通知可能延迟或丢失，也不是安全通信。ECMenu 用它触发已认证拉取；单靠通知不能证明所有进程在有限时间内必定收敛。[DistributedNotificationCenter](https://developer.apple.com/documentation/foundation/distributednotificationcenter) |
| socket 对端身份 | `getsockopt(LOCAL_PEERTOKEN)` → audit token；`SecTaskCreateWithAuditToken` → SecTask?；`SecTaskValidateForRequirement` → Bool 或 throws | 使用运行进程的 Lightweight Code Requirements；失败或不匹配在业务正文前终止。要求精确 identifier、相同 Team、development 签名类别和已签名/动态有效 flags。[SecTaskValidateForRequirement](https://developer.apple.com/documentation/lightweightcoderequirements/sectaskvalidateforrequirement%28task%3Arequirement%3A%29)、[ProcessCodeRequirement](https://developer.apple.com/documentation/lightweightcoderequirements/processcoderequirement)、[项目 IPC](../../Technical/Runtime/IPC.md) |
| 不覆盖写入 | Data、候选 URL、`.withoutOverwriting` → Void 或 Error | 已有目标导致失败；不能与 `.atomic` 组合。模板索引的原子替换与新文件的排他创建是不同操作。[写入选项](https://developer.apple.com/documentation/foundation/nsdata/writingoptions)；本地 macOS 26.5 SDK `Foundation.framework/Headers/NSData.h:25–27` |
| 单文件结果定位 | 文件路径、空 root → Bool | `selectFile` 在 main viewer 中选择，并可能激活 Finder/打开窗口；不能表示精确写回菜单来源窗口。[selectFile](https://developer.apple.com/documentation/appkit/nsworkspace/selectfile%28_%3Ainfileviewerrootedatpath%3A%29)、本地 SDK `AppKit.framework/Headers/NSWorkspace.h:48–50` |
| 批量结果定位 | 输出 `[URL]` → Void | `activateFileViewerSelecting` 激活 Finder 并打开一个或多个窗口；没有逐项选择成功回执。[官方契约](https://developer.apple.com/documentation/appkit/nsworkspace/activatefileviewerselecting%28_%3A%29) |
| 外部应用打开 | 目标 URLs、应用 URL、OpenConfiguration → callback 的应用对象 / Error | callback 完成的是系统打开请求；外部编辑器加载项目或终端具体呈现需运行验收。该 API 可从任意线程调用，completion 在并发队列。[NSWorkspace.open](https://developer.apple.com/documentation/appkit/nsworkspace/open%28_%3Awithapplicationat%3Aconfiguration%3Acompletionhandler%3A%29) |
| 默认应用打开 | 单个 URL → Bool | 模板打开调用同步的 `NSWorkspace.open(URL)`；Bool 表示系统打开请求的结果，不返回外部编辑或保存完成的回执。[open](https://developer.apple.com/documentation/appkit/nsworkspace/open%28_%3A%29) |
| 隐藏属性 | URL + isHidden → Void 或 Error | 点号名称造成的隐藏不能通过设为 false 消除；符号链接对象行为按项目测试证据解释。[isHidden](https://developer.apple.com/documentation/foundation/urlresourcevalues/ishidden)、[项目可见性决策](../../Technical/Features/Visibility.md) |
| ImageIO 编码 | source/index/options → image?；destination → Finalize Bool | thumbnail 返回 nil 表示无法得到图像；Finalize 成功后编码输出才有效。生成 JPEG Data、排他落盘、写日期是三个阶段。[thumbnail](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex%28_%3A_%3A_%3A%29)、[Finalize](https://developer.apple.com/documentation/imageio/cgimagedestinationfinalize%28_%3A%29) |
| 登录项 | `SMAppService.mainApp` register/unregister → Void 或 throws；status → 系统枚举 | 主应用服务登记后在后续登录启动；批准是独立状态。其他 helper 类型的立即启动/重启行为不适用于本项目主应用。[mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)、[register](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29) |

## 项目观察和待验收点

Finder 回调字段组合、Extension 冷启动主应用、原生文本焦点通知、符号链接属性及窗口/Space 行为沿用已有技术文档中的项目观察。各文档注明不同的 macOS 验证版本，不能合并成一次本轮实测。

本轮直接读取本机 macOS 26.5 SDK 的 `NSData.h`、`NSWorkspace.h`，核对写入选项与结果定位声明；源码与平台观察的适用范围分别见[平台总述](../../Technical/Platform/Main.md)、[模板编辑](../../Technical/Features/NewFile.md)、[图片压缩](../../Technical/Features/ImageCompression.md)。所有重构后的动态验收安排在[迁移计划](Migration.md)。

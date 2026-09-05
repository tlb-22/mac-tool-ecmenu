# 技术文档

本目录记录无法从单个源码位置可靠恢复的知识：外部 API 契约、已经验证的系统行为、跨进程与权限边界，以及这些事实所约束的设计选择。产品行为和验收边界以 [Requirements](../Requirements/Main.md) 为准；具体控制流、类型结构和文件职责由源码、文档注释与测试表达。

涉及平台行为时，文档明确区分 Apple SDK 契约、项目观察、推断和项目设计。

## 项目结构

顶层目录按运行目标和所有权划分；下列结构只记录稳定职责，不枚举具体源码文件：

```text
ECMenu/                         主应用
├── App/                        进程与配置会话生命周期
├── Settings/                   设置界面与系统适配器
├── MenuConfiguration/          配置真相源
├── IPC/                        应用侧进程边界
└── ContextCommands/            命令执行与用户反馈
ECMenuFinderExtension/          Finder Extension
├── App/                        Extension 生命周期
├── MenuConfiguration/          配置只读副本
├── IPC/                        请求发送
└── ContextMenu/                Finder 上下文与菜单构建
ECMenuShared/                   两个产品目标的共享契约与无场景原语
Tests/                          单元测试、集成测试与独立界面预览
design/AppIcon/                 应用图标设计源与生成产物
scripts/                        构建、运行、测试与交付入口
spec/                           当前需求、技术知识与未来提案
```

右键功能分别在 `ECMenuShared/ContextCommands/Features/<功能>/`、`ECMenuFinderExtension/ContextMenu/Features/<功能>/` 和 `ECMenu/ContextCommands/Features/<功能>/` 保存共享契约、Finder Feature 与主应用 Handler。`ContextMenuComposition` 和 `ContextCommandComposition` 分别注册调用端与执行端能力；共享目标不维护第三份独立的产品注册表或执行编排。

## 导航

- [运行时](Runtime/Main.md)：进程职责、应用生命周期、IPC、命令执行、进度与配置同步。
- [平台边界](Platform/Main.md)：macOS 与 Finder API 契约、项目实测和文件访问约束。
- [交付边界](Delivery/Main.md)：构建身份、环境隔离和应用图标交付。
- [功能技术决策](Features/Main.md)：各业务能力依赖的平台 API 与不可由单个源码位置恢复的约束。
- [界面预览目标](PreviewTarget.md)：独立 Preview target 与生产代码的边界。
- [Finder 菜单自动截图](FinderMenuCapture.md)：真实 Finder 菜单的自动驱动、独立窗口捕获、稳定边界与失败经验。
- [自动化脚本的用户焦点恢复](UserFocusRestoration.md)：自动化结束后的前台应用恢复、嵌套边界与 macOS Space 行为。
- [测试期间的 Finder 窗口保持](FinderWindowPreservation.md)：窗口集合核对、失败退出与无需新增授权的检查边界。

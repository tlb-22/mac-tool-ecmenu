# 技术文档

本目录记录无法从单个源码位置可靠恢复的知识：外部 API 契约、已经验证的系统行为、跨进程与权限边界，以及这些事实所约束的设计选择。产品行为和验收边界以 [Requirements](../Requirements/Main.md) 为准；具体控制流、类型结构和文件职责由源码、文档注释与测试表达。

涉及平台行为时，文档明确区分 Apple SDK 契约、项目观察、推断和项目设计。具体实现以源码和测试为唯一来源，技术文档只提供理解所需的导航。

## 平台与系统边界

- [Finder 集成边界](FinderIntegration.md)：菜单上下文 API、快照生命周期、菜单过滤、监听范围、外置卷、结果选择与 Extension 状态。
- [进程、交付与权限边界](ExecutionArchitecture.md)：主应用与 Finder Extension 的职责、认证后单次命令投递、命令进度的平台证据与界面预览边界、信任边界和文件访问权限。
- [菜单可见性配置](MenuConfiguration.md)：配置模型、主应用所有权与 Extension 本地副本。
- [应用图标交付](AppIconDelivery.md)：系统遮罩契约、旧式图标自动适配观察与 Icon Composer 分层交付边界。

## 功能技术决策

- [新建 TXT](NewTextFile.md)：不覆盖写入的 SDK 契约与并发观察，以及 Finder 自动选择的边界。
- [拷贝路径](CopyPath.md)：路径对象存在性和系统剪贴板表示。
- [隐藏项目 / 显示项目](Visibility.md)：菜单生成条件、隐藏属性、点号名称与符号链接。
- [进入外部应用](OpenInApplications.md)：文件系统目标语义与 Launch Services 边界。
- [压缩图片](ImageCompression.md)：ImageIO 能力判断、参数窗口并发、进度、安全取消边界与图像转换语义。

# 新建 TXT 技术决策

产品行为见[新建 TXT 需求](../Requirements/NewTextFile.md)。Finder 菜单目标、外置卷覆盖、结果选择 API 和权限边界分别见 [Finder 集成边界](FinderIntegration.md) 与[进程、交付与权限边界](ExecutionArchitecture.md)。

## 不覆盖创建的证据边界

### SDK 契约

Xcode 26.6（17F113）附带的 macOS 26.5 SDK 将 `NSDataWritingWithoutOverwriting` 定义为防止替换既有文件的写入选项，并明确它不能与 `NSDataWritingAtomic` 组合（`NSData.h:25–27`）。该契约规定目标已经存在时不得覆盖，但没有公开 Foundation 使用的系统调用，也没有单独声明跨进程事务或任意写入中断下的 crash-atomic 保证。

### 项目设计与观察

名称候选按需求定义的顺序产生，每个候选直接交给 `Data.write(to:options: .withoutOverwriting)`，不在应用层先读取“可用文件名”再执行普通覆盖写入。系统报告目标已存在时继续下一个候选，其他错误立即结束。

[NewTextFileTests](../../Tests/EnhancedContextMenuTests/ContextCommands/Features/NewTextFile/NewTextFileTests.swift) 使用同一进程中的并发工作线程竞争候选名称，并验证预先存在的文件内容不变、各次创建结果互不重名。这是当前运行环境中的同进程压力观察，不是跨进程测试，也不提供 Foundation 内部原子实现的证据。产品依赖的是 SDK 规定的“不覆盖既有目标”结果，而不是未公开的具体实现方式。

## Finder 自动选择

单一创建结果选择空根路径的 `NSWorkspace.selectFile`，请求 Finder 在 main viewer 中自动选中新文件。窗口与来源选择限制由 [Finder 集成边界](FinderIntegration.md)统一说明；本功能不模拟输入，也不进入重命名模式。

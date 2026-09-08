# 新建文件技术决策

产品行为与实施状态见[新建文件需求](../../Requirements/Features/NewFile.md)。Finder 菜单目标、外置卷、结果选择和权限边界分别见 [Finder 菜单语义](../Platform/Finder/ContextMenus.md)、[Finder 管理位置](../Platform/Finder/ManagedLocations.md)、[Finder 结果选择](../Platform/Finder/ResultSelection.md)和[文件访问](../Platform/FileAccess.md)。

## 模板身份与名称

模板能力的实施约束是：每个模板以软件生成的唯一、稳定 ID 关联元数据和内部文件。菜单显示名与默认文件名均可重复，不能作为存储键、文件查找依据或跨进程命令中的模板身份。名称修改只改变对应属性，保持模板身份和内容关联。

菜单项按模板 ID 绑定用户选择，主应用按同一身份解析模板。已删除或不可读取的模板形成运行时失败，不按名称寻找替代项。这使同名模板和菜单展示后的模板删除都具有明确语义。

## 不覆盖创建的证据边界

### SDK 契约

Xcode 26.6（17F113）附带的 macOS 26.5 SDK 将 `NSDataWritingWithoutOverwriting` 定义为防止替换既有文件的写入选项，并明确它不能与 `NSDataWritingAtomic` 组合（`NSData.h:25–27`）。该契约规定目标已经存在时不得覆盖，但没有公开 Foundation 使用的系统调用，也没有单独声明跨进程事务或任意写入中断下的 crash-atomic 保证。

### 项目设计与观察

当前空白 TXT 创建路径按需求定义的顺序产生名称候选，每个候选直接交给 `Data.write(to:options: .withoutOverwriting)`，不先读取“可用文件名”再执行普通覆盖写入。系统报告目标已存在时继续下一个候选，其他错误立即结束。

[NewTextFileTests](../../../Tests/ECMenuTests/ContextCommands/Features/NewTextFile/NewTextFileTests.swift) 使用同一进程中的并发工作线程竞争候选名称，并验证预先存在的文件内容不变、各次创建结果互不重名。这是当前运行环境中的同进程压力观察，不是跨进程测试，也不提供 Foundation 内部原子实现的证据。产品依赖 SDK 规定的“不覆盖既有目标”结果，而不是未公开的具体实现方式。

这些实测覆盖空文件创建，尚未验证非空模板与二进制文件复制。模板实现需要验证内容保真、同名模板身份、目标重名和并发不覆盖，不能把空文件测试视为模板复制已经通过的证据。

## Finder 自动选择

单一创建结果使用空根路径的 `NSWorkspace.selectFile`，请求 Finder 在 main viewer 中选中新文件。窗口与来源选择限制由 [Finder 结果选择](../Platform/Finder/ResultSelection.md)统一说明；本功能不模拟输入，也不进入重命名模式。

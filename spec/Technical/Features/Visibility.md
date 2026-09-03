# 隐藏项目 / 显示项目技术决策

产品行为见[隐藏项目 / 显示项目需求](../../Requirements/Features/Visibility.md)，Finder 上下文的形成规则见 [Finder 菜单语义](../Platform/Finder/ContextMenus.md)。

## 隐藏属性与点号名称

macOS 26.5 SDK 的 `NSURL.h:226` 声明 `NSURLIsHiddenKey` 是可读写的布尔资源键，表示通常不向用户显示的资源。官方注释同时明确：如果隐藏来自文件名以 `.` 开头，把该键设为 `false` 不会改变其隐藏状态。

普通名称对象通过 Swift 对应的 `URLResourceValues.isHidden` 修改 Finder 隐藏属性。[VisibilityTests](../../../Tests/ECMenuTests/ContextCommands/Features/Visibility/VisibilityTests.swift) 固化了普通文件、目录和符号链接的隐藏与显示、非递归执行、链接目标不变以及点号对象被跳过这些边界。

项目观察表明，点号开头名称的隐藏语义来自文件名本身，清除 `isHidden` 后仍被系统视为隐藏。此类对象不能在“不重命名”的产品边界内真正显示，因此计划阶段静默跳过，而不报告虚假的成功。

## 菜单生成条件

Finder 只从 `.items` 快照构造可见性命令；命令负载直接保存非空的 `FinderItemSelection`，而不是可以继续表达 container 或 sidebar 的通用上下文。因此主应用执行端不需要再次判断和拒绝这些不可能状态。

items 菜单根据普通名称对象的已知 `isHidden` 值决定叶子是否进入布局：至少一个可见对象促成“隐藏项目”，至少一个隐藏对象促成“显示项目”。点号名称和读取失败的对象不促成任何一项出现；混合选择可以同时生成两项。

菜单构建阶段只读取隐藏状态，不预检对象或父目录的写入权限及卷状态。这些条件可能在菜单展示后改变，也可能在 Extension 与主应用中得到不同结果；真正的写入和错误分类属于主应用执行边界。

[ContextMenuCompositionTests](../../../Tests/ECMenuFinderExtensionTests/ContextMenu/ContextMenuCompositionTests.swift) 固化了点号名称和未知状态被排除、混合状态同时生成两项，以及背景和侧边栏不生成可见性命令。

## 符号链接

项目测试确认，设置符号链接 URL 的 `isHidden` 修改链接目录项自身，不修改链接目标。隐藏与显示因而保留 Finder 选择的对象身份，不解析符号链接。

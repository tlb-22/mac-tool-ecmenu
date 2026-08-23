# 隐藏项目 / 显示项目技术决策

产品行为见[隐藏项目 / 显示项目需求](../Requirements/Visibility.md)，container、items 和 sidebar 的形成规则见 [Finder 集成边界](FinderIntegration.md)。

## 隐藏属性与点号名称

macOS 26.5 SDK 的 `NSURL.h:226` 声明 `NSURLIsHiddenKey` 是可读写的布尔资源键，表示通常不向用户显示的资源。官方注释同时明确：如果隐藏来自文件名以 `.` 开头，把该键设为 `false` 不会改变它的隐藏状态。

普通名称对象通过 Swift 层对应的 `URLResourceValues.isHidden` 修改 Finder 隐藏属性。[VisibilityTests](../../Tests/EnhancedContextMenuTests/ContextCommands/Features/Visibility/VisibilityTests.swift) 固化了普通文件、目录和符号链接的隐藏与显示、非递归执行、链接目标不变以及点号对象被跳过这些边界。

项目观察表明，以 `.` 开头的名称由文件名本身产生隐藏语义，清除 `isHidden` 后仍被系统视为隐藏。此类对象不能在“不重命名”的产品边界内真正显示，因此计划阶段静默跳过，而不报告虚假的成功。

## 菜单生成条件

Finder 只在 items 上提供可见性命令；container 和 sidebar 不生成“隐藏项目”或“显示项目”，避免把目录直接子项误当成用户明确选择的操作对象。

主应用执行端重复约束同一边界，只接受 `.items`；container、sidebar 和其他迟到或非产品请求返回目标不可用，不枚举目录内容。

items 菜单根据普通名称对象的已知 `isHidden` 值决定叶子是否进入布局：至少一个可见对象促成“隐藏项目”，至少一个隐藏对象促成“显示项目”。点号名称和读取失败的对象不促成任何一项出现；混合选择可以同时生成两项。

菜单构建阶段只读取隐藏状态，不预检对象或父目录的可写性、卷状态或完全磁盘访问权限。这些条件可能在菜单展示后改变，也可能在 Finder Extension 与主应用中得到不同结果；真正的写入和错误分类仍属于主应用执行边界。

[FinderCompositionTests](../../Tests/EnhancedContextMenuFinderExtensionTests/FinderCompositionTests.swift) 固化了点号名称和未知状态被排除、混合状态同时生成两项，以及空白处和侧边栏不生成可见性命令。

## 符号链接

项目测试确认，设置符号链接 URL 的 `isHidden` 修改链接目录项自身，不修改链接目标。隐藏与显示因而保留 Finder 选择的对象身份，不执行符号链接解析。

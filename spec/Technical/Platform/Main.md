# 平台边界

本目录记录 ECMenu 依赖的 macOS 平台契约、项目实测与由此形成的稳定约束。Finder 专属行为见 [Finder](Finder/Main.md)，文件访问授权见[文件访问](FileAccess.md)。

## 证据范围

- **SDK 契约**来自 Xcode 26.6（17F113）附带的 macOS 26.5 SDK；具体文档注明所依据的头文件或官方接口。
- **项目观察**来自 macOS 26.6.1（25G76）上的本项目人工验收，只证明该验证环境中的行为。
- **项目设计**是根据契约和观察形成的当前约束，不代表 Apple 对未公开行为的承诺。

仓库没有保留早期 Finder 原始回调日志和视觉对比截图。依赖 Finder 字段组合、host 布局或登记行为的结论在 macOS 或 Xcode 升级后必须按对应文档重新验收。

## 导航

- [Finder](Finder/Main.md)：菜单、图标、管理范围、结果选择和 Extension 生命周期。
- [文件访问](FileAccess.md)：Sandbox、TCC、POSIX 权限、只读文件系统和 SIP 的边界。

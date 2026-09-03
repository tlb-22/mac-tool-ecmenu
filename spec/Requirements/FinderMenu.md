# Finder 菜单

## 结构与顺序

当前命令直接进入 Finder 一级右键菜单，不增加统一的产品父菜单或功能子菜单。

菜单按以下顺序排列，命令之间不插入分隔线：

| 顺序 | 英文 | 简体中文 |
|---|---|---|
| 1 | `New TXT File` | `新建 TXT` |
| 2 | `Copy Path` | `拷贝路径` |
| 3 | `Hide Items` | `隐藏项目` |
| 4 | `Show Items` | `显示项目` |
| 5 | `Compress Images` | `压缩图片` |
| 6 | `Open in Visual Studio Code` | `进入 Visual Studio Code` |
| 7 | `Open in iTerm2` | `进入 iTerm2` |

每个命令使用固定且符合功能语义的图标；同一命令在 Finder 菜单、状态页和进度窗口中使用一致的名称与图标。

## 显示规则

核心原则是，当一个命令不可用、或能简单确认操作无结果时，则不显示该命令。具体来说，菜单叶子符合以下任一条件时不显示：

- 用户关闭了对应命令的显示开关。
- 当前 Finder 上下文没有对应语义。
- 命令依赖的外部应用不可用。
- 根据菜单构建时已经获得的状态，可以确定没有任何对象需要改变。

其余语义适用的命令均显示且可用。菜单构建不预检文件或父目录写权限、卷是否只读以及“完全磁盘访问”状态；这些条件只在执行命令时检查。

关闭总开关后不显示任何 ECMenu 命令，但保留各命令原有的显示配置。总开关与各命令开关的界面行为见[状态页](StatusPage.md)。

每个命令适用的 Finder 上下文由对应功能需求唯一规定：

- [新建 TXT](Features/NewTextFile.md#菜单与目标目录)
- [拷贝路径](Features/CopyPath.md#菜单与操作对象)
- [隐藏项目 / 显示项目](Features/Visibility.md#操作对象)
- [压缩图片](Features/ImageCompression.md#菜单与输入)
- [进入外部应用](Features/OpenInApplications.md#菜单与目标)

对应技术设计见[Finder 上下文菜单](../Technical/Platform/Finder/ContextMenus.md)。

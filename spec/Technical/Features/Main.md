# 功能技术决策

本目录按产品功能保存外部 API 边界、跨进程约束和无法从单个源码位置恢复的设计动机。产品行为与验收边界见[功能需求](../../Requirements/Features/Main.md)。

- [新建 TXT](NewTextFile.md)：不覆盖写入的 SDK 契约、并发观察和 Finder 自动选择。
- [拷贝路径](CopyPath.md)：路径对象存在性和系统剪贴板表示。
- [隐藏项目 / 显示项目](Visibility.md)：隐藏属性、点号名称、菜单条件和符号链接。
- [进入外部应用](OpenInApplications.md)：文件系统目标语义与 Launch Services 边界。
- [压缩图片](ImageCompression.md)：ImageIO 能力判断、参数窗口、进度、取消与图像转换语义。

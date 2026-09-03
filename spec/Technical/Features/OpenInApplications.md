# 进入外部应用技术决策

产品行为见[进入外部应用需求](../../Requirements/Features/OpenInApplications.md)，Finder 菜单目标的形成规则见 [Finder 菜单语义](../Platform/Finder/ContextMenus.md)。

## 文件系统目标身份

目标存在性和目录类型使用 `FileManager.fileExists(atPath:isDirectory:)` 读取。该检查跟随符号链接判断最终对象，所以断链不可用；执行时仍把 Finder 提供的原始 URL 交给外部应用，不用解析后的目标路径替换用户选择。

package 不读取 Finder 的 package 标记，只采用文件系统目录事实。因此 `.app`、`.framework` 等目录可以作为 VS Code 项目或 iTerm2 工作目录；这是产品语义，不是 Launch Services 对 package 的特殊处理。

## Launch Services 边界

固定应用通过 bundle identifier 交给 `NSWorkspace.urlForApplication(withBundleIdentifier:)` 定位，再使用 `NSWorkspace.open(_:withApplicationAt:configuration:)` 打开原始目标 URL。该方案不依赖应用显示名称、shell、`open` 命令、VS Code CLI 或用户的 `PATH`，也不构造可注入的命令字符串。

主应用和 Finder Extension 分别在自身进程中通过相同的 Launch Services 查询判断应用是否可定位。主应用把结果呈现为设置行状态，Extension 在生成菜单时省略缺失应用的命令。两次查询之间应用仍可能被安装、移动或删除，因此实际打开保留独立的失败处理。

成功回调只表示系统打开请求成功返回，不表示外部应用已经完成项目加载。VS Code 是否复用窗口、iTerm2 是否把目录 URL 设为新窗口工作目录，属于外部应用验收边界；外部应用版本升级后需要分别手动复验。

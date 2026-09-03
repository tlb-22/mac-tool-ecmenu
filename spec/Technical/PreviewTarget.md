# 界面预览目标

界面预览由独立的沙箱 macOS App target 承载。它在单独进程中复用生产 renderer 和共享契约，只在开发边界注入合成状态；产品主应用不包含预览分支，预览应用也不启动 IPC、嵌入 Finder Extension、参与产品归档或改变正在运行的产品生命周期。

预览不是自动化 UI 测试。唯一 Composition 注册全部 Preview ID，稳定 runtime 只解析 ID、验证注册唯一性并维持对应会话；各 Case 集中保存模拟参数，并复用生产呈现类型或呈现边界。完整测试保证 Preview target 可编译且入口可列出，可见结果仍由人工检查。

预览源码位于 `Tests/ECMenuPreviews/`，构建和运行入口见[开发脚本](../../scripts/Main.md#界面预览)。

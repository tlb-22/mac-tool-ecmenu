# 界面预览目标

界面预览由独立的沙箱 macOS App target 承载。它在单独进程中复用生产 renderer 和共享契约，只在开发边界注入合成状态；产品主应用不包含预览分支，预览应用也不启动 IPC、嵌入 Finder Extension、参与产品归档或改变正在运行的产品生命周期。

预览不是自动化 UI 测试。唯一 Composition 注册全部 Preview ID，稳定 runtime 解析 ID、验证注册唯一性并维持对应会话；各 Case 以独立 ID 固定一种可见状态，并复用生产呈现类型或呈现边界。完整测试保证 Preview target 可编译且入口可列出，可见结果仍由人工检查。

启动脚本可向单次预览进程传入 `-AppleLanguages (en)` 或 `-AppleLanguages (zh-Hans)`，分别检查英文和简体中文；未指定时不覆盖系统语言。语言只存在于进程启动参数中，预览和产品界面无需维护额外的 Locale 状态。

批量截图脚本构建一次 Preview target，从注册表验证全部或调用方指定的场景，并串行捕获每个场景的英文和简体中文版本。Preview runtime 负责激活唯一可见顶层窗口；窗口成为 key window、完成布局和绘制，且窗口编号与尺寸跨一轮主循环保持稳定后，才通过标准输出发送 `READY <windowNumber>`。脚本按该窗口编号生成不含阴影的独立窗口截图，圆角外保持透明；截图完成后，runtime 再确认应用与窗口在整段捕获期间没有失焦，只保留通过确认的图片。截图不依赖辅助功能或外部模拟点击，批量截图与交互预览互斥运行。

README 设置页场景与状态覆盖场景使用不同 Preview ID：前者固定全部开关开启，并在 Preview 边界通过 Launch Services 严格读取所需外部应用的真实图标；后者继续保留未批准、未启用和应用缺失等状态。两者只共享生产 renderer 与无副作用的预览会话，不向产品代码加入文档截图分支。

预览源码位于 `Tests/ECMenuPreviews/`，构建和运行入口见[开发脚本](../../scripts/Main.md#界面预览)。

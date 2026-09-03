# 本地化

产品以英文（`en`）为源语言，并提供简体中文（`zh-Hans`）翻译。主应用和 Finder Extension 是独立 Bundle，分别由 `ECMenu/Localizable.xcstrings` 与 `ECMenuFinderExtension/Localizable.xcstrings` 提供运行时字符串；固定产品名不使用 `InfoPlist.strings`。

`ECMenuShared` 以 `LocalizedStringResource` 保存命令等跨端显示语义，不提前解析为文字。主应用和 Extension 在各自的呈现边界通过当前进程的主 Bundle 解析资源，因此状态页、进度窗口和 Finder 菜单共享语义，而资源仍归各自 Bundle 所有。语言选择不进入持久化配置或 IPC。

产品跟随 macOS 的语言选择，不实现应用内切换。主应用与 Extension 都只保证在进程启动时取得当前语言；切换系统语言后的人工验收须重新启动主应用，并重启 Finder 以重新加载 Extension，再检查真实 Finder 菜单，不能只验证主应用或 Preview。

# 项目工作规范

## 构建、测试与产物

- 项目相关的构建、测试和运行产物必须留在仓库内，不使用系统临时目录保存它们。
- `.derivedData/` 只作为 Xcode Derived Data 根目录；脚本可以读取其中的构建产品，但不得在其中创建自定义日志、测试 fixture、探针、截图或发布物。
- `.artifacts/scratch/` 只保存一次运行或调查产生的可重建内容，按 `logs/`、`tests/`、`probes/`、`previews/` 分类。单次运行产物的顶层文件或目录使用 `YYYYMMDD-HHMMSS-<purpose>-<pid>` 命名；没有相关任务运行时，整个 `scratch/` 均可删除。
- 可重复执行的测试、诊断和预览定义分别维护在 `Tests/`、`scripts/` 和 `Previews/`；源码、正式配置和持久文档不得依赖 `scratch/`，需要保留的结论写入相应文档。
- 正式交付物位于 `.artifacts/releases/<version>+<build>/`；已有的非空版本目录不得静默覆盖。
- 日常 Debug 构建与运行使用 `./scripts/run-debug.sh`，完整测试使用 `./scripts/test.sh`；共享 `.derivedData/` 或 Finder 登记状态的脚本顺序执行。删除 `.derivedData/` 前，先停止并注销从其中运行的应用和 Finder Extension。
- 图标变化但程序坞仍显示旧缓存时使用 `./scripts/run-debug.sh --refresh-icon`；Finder Extension 源码变化、菜单消失或扩展未加载时使用 `./scripts/run-debug.sh --refresh-finder`。

## Git 操作

- 除非用户单独运行，否则自动化代理不得执行 `git add` 或以其他方式修改 Git 暂存区；所有暂存操作由用户完成。

## Finder Extension 调试

- Extension 是否启用、是否登记、是否运行是三个独立状态；菜单消失时先区分加载失败与菜单代码返回空结果。
- 重新构建后须确认系统登记和运行进程都指向 `.derivedData/Build/Products/` 中的当前 Debug 产物；Finder 持有旧进程时执行完整刷新并再次验证，不能只重新打开主应用。

## 项目文档

- 渐进展开的文档编写模式：从各目录的 `Main.md` 开始阅读；它只保留总述、关键结论和导航，细节文件各自承担一个清晰主题。
- 语言的马尔可夫性：改了主意只留最终态 Y，像 X 从未出现，不写「本来想 X，其实 Y 更好」，除非是对产品的已知限制和明确边界。
- 临时待办只记录未完成工作；完成后删除对应条目，不保留过程历史。
- `spec/Requirements/` 记录产品行为与验收边界，不记录具体视觉细节选择，例如视觉参数/图标名称；`spec/Technical/` 记录外部契约、项目实测、跨模块约束和无法从源码可靠恢复的设计动机。源码已清楚表达的实现不重复写入文档。
- 平台结论须区分官方契约、项目观察与推断，并说明验证版本或证据限制。
- `reference/<项目>/` 保存注明版本的外部源码快照，其 `.Analysis/` 只分析该项目；本项目的采用与取舍写入 `spec/Technical/`。
- 文档只保留当前有效结论，语言简洁完整；行为或技术边界变化时同步更新对应需求、技术文档和链接，并删除被新结构替代的重复内容。

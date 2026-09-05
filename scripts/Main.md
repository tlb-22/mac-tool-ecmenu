# 开发脚本

脚本从自身位置解析项目根目录。`.derivedData/` 只作为 Xcode Derived Data；脚本日志、测试工作目录、临时探针和视觉检查分别写入 `.artifacts/scratch/{logs,tests,probes,previews}/`。scratch 中每次运行的文件或目录使用 `YYYYMMDD-HHMMSS-<purpose>-<pid>` 命名，可在没有相关任务运行时整体清理；需要重复执行的测试与界面预览保存在 `Tests/`，诊断入口保存在 `scripts/`。

正式发布产物写入 `.artifacts/releases/<version>+<build>/`，已有非空版本目录不得被静默覆盖。`design/AppIcon/output/Preview/` 是图标设计源包自己的可重建预览输出，不属于运行时 scratch。

## 用户焦点恢复

会驱动主应用、Preview 或 Finder 的自动化入口在运行前记录当前前台应用，并在自身清理完成后将焦点交还给同一应用实例：`run-debug.sh`、`test.sh`、`test-integration.sh`、`activate-environment.sh`、`capture-previews.sh`、`capture-finder-menus.sh` 和 `capture-readme-images.sh`。嵌套调用只由最外层入口记录和恢复一次，因此 README 截图流程不会在中途被子脚本切回原应用。

普通应用退出后不会被脚本重新启动；Finder 因部分流程会主动重启，可恢复到身份唯一匹配的新 Finder 进程。没有前台应用的 CI 会话直接跳过恢复。`preview-ui.sh` 用于把可交互的 Preview 留在前台，不执行恢复。实现依据与 macOS Space 边界见[自动化脚本的用户焦点恢复](../spec/Technical/UserFocusRestoration.md)。

## 测试期间的 Finder 窗口检查

`test.sh` 与 `test-integration.sh` 在开始时记录 Finder 普通窗口的 ID 集合，在测试清理和焦点恢复全部结束后重新读取；新增、丢失或等量替换窗口都会使测试失败。最小化及非屏幕上的窗口也参与比较，窗口前后顺序不影响结果。成功、失败以及 HUP、INT、TERM 中断均执行检查，原测试已经失败时保留其退出码。嵌套测试只由最外层检查一次。

检查只读取窗口元数据，无需辅助功能或屏幕录制授权，也不会自动关闭窗口。没有 GUI 会话时明确跳过；运行期间手动开关 Finder 窗口也会形成差异。前后快照保存在 `.artifacts/scratch/tests/YYYYMMDD-HHMMSS-finder-windows-<pid>/`，对应日志保存在 `scratch/logs/` 的同名目录。纯窗口比较及退出路径测试分别位于 `Tests/FinderWindowPreservation/` 与 `Tests/DevelopmentScripts/`。检查范围与平台依据见 [Finder 窗口保持](../spec/Technical/FinderWindowPreservation.md)。

## 构建与运行

```bash
./scripts/run-debug.sh
```

该命令执行签名 Debug 构建，只结束该构建产物精确路径上的旧主应用，运行 `.derivedData/Build/Products/Debug/ECMenu(Debug).app`，并验证主应用和 Finder Extension 进程。脚本从 Xcode build settings、构建后的 Info.plist 与代码签名解析产品路径和 Debug 身份，不按写死的产品名或进程名操作，因此不会结束已安装的 Release 主应用。

环境切换分两阶段复用此入口：`--build-only` 只构建并验证产品身份与签名；`--no-build` 使用现有产品，重新验证身份与签名后执行运行步骤。两者互斥，`--build-only` 单独使用。日常构建与运行使用默认模式。

应用图标变化而程序坞仍显示旧缓存时使用：

```bash
./scripts/run-debug.sh --refresh-icon
```

该模式注销当前 Debug 应用，结束用户级 IconServices 与程序坞，删除可重建的用户级图标缓存，再登记当前应用和 Finder Extension，并打开项目目录触发 Extension 按需加载。它不保留缓存备份，也不重启 Finder；只在图标变化且普通重开仍显示旧图时使用。

Finder Extension 源码变化、菜单消失或扩展没有加载时使用：

```bash
./scripts/run-debug.sh --refresh-finder
```

该模式先登记当前 Debug 应用与扩展，再移除同一 Extension 身份的其他旧路径及其父应用登记，保留并启用当前路径；随后只按当前 Debug Extension 的精确可执行路径结束旧进程，通过 Finder 的用户级 launchd service 重启 Finder，并打开项目目录触发加载。脚本不会注销、停用或结束不同身份的 Release 版本；若发现同一产品的另一 Finder Extension 身份仍处于启用状态，会在改变任何非 Debug 登记前停止并要求先在系统设置中明确停用，避免两个扩展同时贡献重复菜单。脚本在等待进程前验证 Debug 登记唯一性，并为 Finder 冷启动保留 15 秒加载时间。内部截图流程会同时传入 `--no-open-finder-window`，跳过项目目录窗口。

## 完整测试

```bash
./scripts/test.sh
```

成功时输出通过数量，并验证独立 Preview target 可编译、声明式注册表可列出。完整日志写入 `.artifacts/scratch/logs/` 中带时间的单次文件；测试 result bundle 位于 `.artifacts/scratch/tests/YYYYMMDD-HHMMSS-xctest-<pid>/ECMenu.xcresult`，其他测试 fixture 也只存在于对应的单次目录。失败时脚本输出对应日志尾部。

环境切换测试位于 `Tests/DevelopmentScripts/`：在项目内隔离目录运行生产切换脚本，以外部命令替身验证准备失败、状态查询失败、激活失败、信号中断和恢复失败的处理顺序，不改变系统登记或启用状态。测试命令路径只包含隔离替身与 macOS 系统目录，Python 替身使用当前测试解释器。

## 跨进程集成测试

```bash
./scripts/test-integration.sh
```

该脚本先通过 `run-debug.sh --build-only` 准备并验证当前签名 Debug 产品，再构建产品 bundle identifier 为 `com.axiomace.ecmenu.test.ipcsender` 的 `ContextCommandSender`。该本地 helper 使用真实 Apple Development 签名，并有意把代码签名 identifier 覆盖为当前 Finder Extension 身份，同时声明共同 App Group entitlement。脚本从实际构建的 Debug Extension 派生 Team 与 identifier，核对其 Info.plist、代码签名和 helper 身份一致。

验证准备完成后，脚本按当前 Debug 主应用的精确可执行路径停止旧进程并等待退出，再普通打开当前应用、确认进程运行。只读配置查询在五秒总预算内等待新宿主就绪；仅连接端点不存在或没有监听者时重试，身份不符和其他失败立即终止。随后向 scratch 中的一个普通名文件单次发送隐藏命令，读取实际文件 flags，确认 `UF_HIDDEN` 已设置；命令不重试。测试工作目录位于 `.artifacts/scratch/tests/`，完整输出位于 `.artifacts/scratch/logs/`；两者均按单次运行命名。

跨进程验证不刷新 Finder，也不操作 Finder 窗口。真实 Finder 菜单、Extension 加载与点击链路属于独立的运行验收，使用 `run-debug.sh --refresh-finder` 及下列人工步骤验证。Finder host 的 URL 打开入口不属于主应用冷启动恢复保证。

## Release 构建

发布前依次执行图标一致性检查、完整测试和跨进程集成测试：

```bash
./scripts/generate-app-icon.sh --check
./scripts/test.sh
./scripts/test-integration.sh
```

随后构建当前 Xcode Release configuration：

```bash
./scripts/build-release.sh
```

该脚本从 Xcode build settings 读取版本、build、产品名和签名配置，使用 generic macOS destination 创建 Archive，并拒绝覆盖非空的 `.artifacts/releases/<version>+<build>/`。正式目录保存 `ECMenu.xcarchive`、包含完整应用 bundle 的版本化 ZIP 与 `SHA256SUMS`；Archive 保留主应用和 Finder Extension 的 dSYM。完整构建日志与解压复验工作目录仍分别位于 `.artifacts/scratch/logs/` 和 `.artifacts/scratch/probes/`。

脚本验证主应用与 Finder Extension 的版本、Bundle/signing identifier、Team、App Group、sandbox entitlement、代码签名和 dSYM UUID，并在 ZIP 解压后再次验证签名。当前发布边界固定为 Personal Team 的 Apple Development 签名，不执行 Developer ID export、公证、staple 或 `spctl` 放行检查；首次运行仍由用户按 macOS 界面手动放行。

Archive 和打包不改变本机的 Extension 启用状态。Debug 与 Release 的应用、登记、偏好和 IPC 可以同时存在，但两个 Finder Extension 不得同时启用。安装版已经位于 `/Applications` 后，使用以下命令切换当前 Finder 环境：

```bash
./scripts/activate-environment.sh debug
./scripts/activate-environment.sh release
```

脚本先完成目标准备：Debug 构建并验证产品，Release 定位并验证 `/Applications` 中的安装版；准备失败保留现有启用状态。随后记录两个身份的启用状态，先停用另一身份，再登记并启用目标身份，通过 Finder 的用户级 launchd service 重启 Finder，验证登记与运行路径。Debug 激活复用已准备的构建产品，Release 使用安装版；两者都先登记目标路径，再清理同身份的其他旧路径，使清理失败时目标仍有可启用的登记。

切换失败或收到 HUP、INT、TERM 时，脚本先停用原本未启用的身份，再恢复原本启用的身份，并重启 Finder。恢复启用状态不撤销已经完成的目标构建或登记更新；恢复失败会明确报告并保留失败日志。两套主应用不因切换而互相退出，脚本不注销非目标身份或删除其数据。

真正的首次安装验收在没有登记过 ECMenu 的新 macOS 用户或虚拟机中进行：解压 ZIP、放入 `/Applications`、手动放行并启用 Release Finder Extension，再验证 IPC、登录项、完全磁盘访问、六类命令和卸载边界。这样不会为了 clean-room 验收破坏日常开发账号中的 Debug 环境。

## 生命周期人工验收

先使用 `./scripts/run-debug.sh --refresh-finder` 启动当前 Debug 版本，再完成以下检查：

1. 最小化状态页，确认配置会话仍保持打开，应用仍在程序坞中；随后恢复窗口。
2. 点击状态页关闭按钮，确认状态页和程序坞图标消失，而主应用进程与 Finder Extension 进程仍在运行；在 Finder 执行命令并确认成功。
3. 再次普通打开应用，在状态页按 `Command-W`，确认状态页和程序坞图标消失，而主应用进程仍在运行；在 Finder 执行命令并确认成功。
4. 再次普通打开应用，选择 `Command-Q`，确认状态页和程序坞图标消失，而主应用进程仍在运行；在 Finder 执行命令并确认成功。
5. 在配置会话关闭时执行无界面命令，以及需要参数、错误反馈或进度的命令，确认只出现必要的业务窗口，程序坞图标不出现。
6. 再次普通打开应用，确认复用现有进程、只显示一个状态页，并重新出现在程序坞中。
7. 强制结束主应用进程后触发命令，确认菜单仍可由 Extension 显示，但命令不执行并播放系统默认错误提示音；重新打开应用后确认命令恢复。
8. 在系统未登记本应用登录项时打开“通用”，确认“登录时打开”默认关闭；开启后，系统已批准时不显示额外状态文字，需要批准时保持开关开启并显示灰色“未批准”。从系统设置返回应用后，确认状态自动刷新。
9. 获得系统批准后，让主应用保持运行并注销、重新登录；确认系统不会恢复上次配置会话，主应用只作为后台命令宿主启动，状态页和程序坞图标均不出现。在 Finder 执行命令并确认成功；随后普通打开应用，确认仍复用该进程并只显示一个状态页。
10. 关闭“登录时打开”，确认当前命令宿主不退出，并确认下一次登录不再自动启动主应用。

## 界面预览

```bash
./scripts/preview-ui.sh status-page-general
./scripts/preview-ui.sh status-page-context-menu
./scripts/preview-ui.sh readme-status-page-general
./scripts/preview-ui.sh readme-status-page-context-menu
./scripts/preview-ui.sh image-compression-settings
./scripts/preview-ui.sh image-compression-settings-validation-error
./scripts/preview-ui.sh context-command-progress-single
./scripts/preview-ui.sh context-command-progress-multiple
./scripts/preview-ui.sh status-page-general --language en
./scripts/preview-ui.sh status-page-general --language zh-Hans
./scripts/preview-ui.sh --list
```

该命令构建并启动独立的 `ECMenuPreviews` macOS 应用。各入口固定呈现设置页状态覆盖、README 正常设置、压缩设置正常与验证错误、单任务与多任务进度；它们复用生产界面，不写入图片或持久化设置，也不执行右键命令。普通状态覆盖场景只注入合成状态；README 场景保持所有开关开启，并额外从 Launch Services 只读 Visual Studio Code 与 iTerm2 的真实图标，任一应用未安装时不会使用占位图标。`--language en` 与 `--language zh-Hans` 通过当前预览进程的 `AppleLanguages` 参数检查对应语言；省略参数时跟随系统语言。`--list` 仍只列出可用 Preview ID。

预览代码位于 `Tests/ECMenuPreviews/`，每个 Case 在文件开头集中保存任务数量等可调参数，并由声明式 Composition 统一注册。

`preview-ui.sh` 只替换独立预览进程，不结束主应用或刷新 Finder Extension；日常主应用运行继续使用 `run-debug.sh`。Xcode 构建产物保存在 `.derivedData/`，完整构建日志位于 `.artifacts/scratch/logs/`；临时截图或视觉检查结果位于 `.artifacts/scratch/previews/`。

一次生成全部 Preview 的中英文窗口截图：

```bash
./scripts/capture-previews.sh
./scripts/capture-previews.sh status-page-general status-page-context-menu
```

该脚本只构建一次，并从 Preview 注册表验证场景；未指定 Preview ID 时捕获全部场景，也可以只捕获指定场景，始终分别生成英文与简体中文版本。每个 Preview 进程先自行激活目标窗口；窗口成为 key window、完成布局且尺寸稳定后，脚本才按窗口编号生成不含阴影的独立窗口截图，圆角外保持透明，并在截图完成后确认捕获期间没有失焦。失焦图片会被删除且本次运行失败。批量截图与交互预览互斥运行；截图和运行日志分别写入带本次时间与进程号的 `.artifacts/scratch/previews/` 与 `.artifacts/scratch/logs/` 目录。截图依赖运行脚本的终端具有“屏幕与系统音频录制”权限，不使用辅助功能权限。

## Finder 菜单截图

```bash
./scripts/capture-finder-menus.sh
./scripts/capture-finder-menus.sh multiple-images
./scripts/capture-finder-menus.sh --language en plain-file
./scripts/capture-finder-menus.sh --language zh-Hans plain-file
./scripts/capture-finder-menus.sh --list
./scripts/capture-finder-menus.sh --list-languages
```

该脚本构建并运行当前 Debug 版本，再为目录背景、普通文件、目录和多张图片建立固定 fixture，打开 Finder 的真实右键菜单并分别截图。默认依次截取英文与简体中文的全部场景；`--language` 可重复传入，也可与场景 ID 组合用于单语言调试。图片和逐场景日志按 `<run>/<language>/<scenario>` 分组。

真实菜单同时包含 Finder 原生项目与 Finder Extension 项目。脚本只临时修改 Finder 和当前 Debug 主应用各自的 `AppleLanguages`；主应用在准备阶段启动一次，此后保持同一 PID，每种语言及最终恢复都只重启 Finder 和 Extension。系统全局语言、地区格式、Release 身份和 Extension 自身偏好均不改变。运行前必须关闭所有 Finder 窗口，脚本在修改偏好前、每个场景后和最终恢复后都会验证没有窗口遗留。

每张图片仍捕获菜单的独立透明窗口，不包含窗口阴影、后方 Finder 窗口或桌面；脚本会分别核对当前语言下的 Finder 原生标志项和该场景必须出现的 ECMenu 命令，并在截图后重新确认 Finder、来源窗口、菜单位置和菜单项均未变化。当前配置中关闭了必需命令时，本次截图会失败，不改写用户配置。

场景定义位于 `Tests/FinderMenuCapture/`：基础上下文集中在 `Contexts/`，各命令的菜单期望位于对应的 `Features/`，图片 fixture 与多图场景由 `Features/ImageCompression/` 持有。Finder 打开、Accessibility 读取和菜单生命周期统一封装在 `Support/`，不向 Finder Extension 加入截图分支。`--check` 验证注册表、fixture、本地化键、辅助程序编译及其静态 TCC 身份配置，已包含在 `test.sh` 与 CI 中；真实 Finder 截图不在无人值守的 CI 中运行。

真实截图运行时需要保持 macOS 桌面已解锁且不要操作 Finder。运行端需要“辅助功能”和“屏幕与系统音频录制”权限；这些权限只用于开发截图工具，ECMenu 产品本身仍不需要辅助功能权限。截图、fixture 和日志使用同一单次运行名称，分别位于 `.artifacts/scratch/{previews,tests,logs}/`。`--check` 只验证场景、语言定义、本地化键、Finder 资源映射、fixture、辅助程序编译及静态 TCC 身份，不修改偏好或重启进程。

平台契约、窗口所有权、透明截图方案和已排除的失败路径见 [Finder 菜单自动截图](../spec/Technical/FinderMenuCapture.md)。

## README 图片

```bash
./scripts/capture-readme-images.sh
```

该脚本复用上述两个截图入口，分别捕获英文与简体中文的 README 正常设置场景和 Finder 目录背景菜单，再按通用设置、右键菜单设置、Finder 菜单的顺序以固定间距合成同尺寸透明图片。设置页中所有开关均开启，外部应用使用本机安装的真实图标；缺少 Visual Studio Code 或 iTerm2 时会在刷新 Finder 前失败。合成过程不裁切来源截图；两个设置页保持原尺寸，作为产品主体的 Finder 菜单放大至 `1.5×`。全部捕获和校验成功后才更新 `.docs/images/overview-en.png` 与 `.docs/images/overview-zh-Hans.png`。纯图片排版由 `Tests/READMEImageCapture/Support/READMEOverviewComposer.swift` 负责，编译产物、来源截图和日志均位于对应的 `.artifacts/scratch/` 运行目录。

该入口持有完整截图过程的互斥锁，并沿用 Finder 菜单截图的零窗口前置条件、语言恢复和权限要求。运行时保持桌面已解锁且不要操作 Finder。

## 应用图标

```bash
./scripts/generate-app-icon.sh
./scripts/generate-app-icon.sh --check
```

`design/AppIcon/` 是唯一设计源包：SVG 保存几何、颜色与设置页命名视窗，JSON 模板保存 Icon Composer 图层、阴影和材质，同目录组合脚本只负责读取、校验、资源拆分与预览验证，并把可重建产物写入 `design/AppIcon/output/`。默认命令重新组合后只同步发生变化的 Xcode 正式资源；`--check` 不写项目资源，只检查它们是否与设计输出一致。设计预览位于 `design/AppIcon/output/Preview/`，详细边界见[应用图标设计源](../design/AppIcon/Main.md)。

所有脚本默认使用 `/Applications/Xcode.app/Contents/Developer` 和 `platform=macOS,arch=arm64`，可通过 `DEVELOPER_DIR` 与 `XCODE_DESTINATION` 覆盖。

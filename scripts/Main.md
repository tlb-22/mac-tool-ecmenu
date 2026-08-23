# 开发脚本

脚本从自身位置解析项目根目录。`.derivedData/` 只作为 Xcode Derived Data；脚本日志、测试工作目录、临时探针和视觉检查分别写入 `.artifacts/scratch/{logs,tests,probes,previews}/`。scratch 中每次运行的文件或目录使用 `YYYYMMDD-HHMMSS-<purpose>-<pid>` 命名，可在没有相关任务运行时整体清理；需要重复执行的测试、诊断入口和界面预览分别保存在 `Tests/`、`scripts/` 和 `Previews/`。

正式发布产物写入 `.artifacts/releases/<version>+<build>/`，已有非空版本目录不得被静默覆盖。`design/AppIcon/output/Preview/` 是图标设计源包自己的可重建预览输出，不属于运行时 scratch。

## 构建与运行

```bash
./scripts/run-debug.sh
```

该命令执行签名 Debug 构建，只结束该构建产物精确路径上的旧主应用，运行 `.derivedData/Build/Products/Debug/ECMenu(Debug).app`，并验证主应用和 Finder Extension 进程。脚本从 Xcode build settings、构建后的 Info.plist 与代码签名解析产品路径和 Debug 身份，不按写死的产品名或进程名操作，因此不会结束已安装的 Release 主应用。

应用图标变化而程序坞仍显示旧缓存时使用：

```bash
./scripts/run-debug.sh --refresh-icon
```

该模式注销当前 Debug 应用，结束用户级 IconServices 与程序坞，删除可重建的用户级图标缓存，再登记当前应用和 Finder Extension，并打开项目目录触发 Extension 按需加载。它不保留缓存备份，也不重启 Finder；只在图标变化且普通重开仍显示旧图时使用。

Finder Extension 源码变化、菜单消失或扩展没有加载时使用：

```bash
./scripts/run-debug.sh --refresh-finder
```

该模式先移除与当前 Debug Extension 具有相同 bundle identifier 的旧登记及其父应用登记，只保留并启用当前 Debug 扩展；随后只按当前 Debug Extension 的精确可执行路径结束旧进程、完整等待 Finder 退出，再重启 Finder 并打开项目目录触发加载。脚本不会注销、停用或结束不同身份的 Release 版本；若发现同一产品的另一 Finder Extension 身份仍处于启用状态，会在改变任何非 Debug 登记前停止并要求先在系统设置中明确停用，避免两个扩展同时贡献重复菜单。脚本在等待进程前验证 Debug 登记唯一性，并为 Finder 冷启动保留 15 秒加载时间。

## 完整测试

```bash
./scripts/test.sh
```

成功时输出通过数量，并验证独立 Preview target 可编译、声明式注册表可列出。完整日志写入 `.artifacts/scratch/logs/` 中带时间的单次文件；测试 result bundle 位于 `.artifacts/scratch/tests/YYYYMMDD-HHMMSS-xctest-<pid>/EnhancedContextMenu.xcresult`，其他测试 fixture 也只存在于对应的单次目录。失败时脚本输出对应日志尾部。

## 跨进程集成测试

```bash
./scripts/test-integration.sh
```

该脚本刷新并运行项目 Debug 应用，随后构建产品 bundle identifier 为 `com.axiomace.ecmenu.test.ipcsender` 的 `ContextCommandSender`；该本地 helper 使用真实 Apple Development 签名，并有意把代码签名 identifier 覆盖为当前 Finder Extension 身份，同时声明共同 App Group entitlement。脚本从实际构建的 Debug Extension 派生 Team 与 identifier，核对其 Info.plist、代码签名和 helper 身份一致后，再通过生产 Unix-domain socket 双向验证身份、单次单向发送一份命令，并确认目标目录最终只创建一个 TXT 文件；随后单独使用请求/响应连接拉取菜单配置。测试工作目录位于 `.artifacts/scratch/tests/`，完整输出位于 `.artifacts/scratch/logs/`；两者均按单次运行命名。

该测试不触发 Finder 菜单，也不验证 Finder Extension 能够冷启动已经退出的主应用。Finder host 的 URL 打开入口不属于当前恢复保证；Extension 点击链路和应用呈现生命周期仍需按下列步骤人工验收。

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

脚本总是先停用另一身份，再启用目标身份并重启 Finder。Debug 模式复用 `run-debug.sh --refresh-finder` 完成构建、登记和运行验证；Release 模式只接受 `/Applications` 中身份和签名配对正确的安装版，清除同一 Release 身份的旧路径后登记并验证当前路径。两套主应用不需要因为切换而退出，脚本不注销非目标身份或删除其数据。

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
./scripts/preview-ui.sh context-command-progress
./scripts/preview-ui.sh status-page
./scripts/preview-ui.sh image-compression-settings
./scripts/preview-ui.sh --list
```

该命令构建并启动独立的 `EnhancedContextMenuPreviews` macOS 应用。三个入口分别显示可调数量的并发任务进度、主程序状态页和压缩图片设置窗口；它们复用生产界面，只注入合成状态，不读写图片、持久化设置或执行右键命令。预览代码位于根级 `Previews/`，每个 Case 在文件开头集中保存任务数量等可调参数，并由声明式 Composition 统一注册。

`preview-ui.sh` 只替换独立预览进程，不结束主应用或刷新 Finder Extension；日常主应用运行继续使用 `run-debug.sh`。Xcode 构建产物保存在 `.derivedData/`，完整构建日志位于 `.artifacts/scratch/logs/`；临时截图或视觉检查结果位于 `.artifacts/scratch/previews/`。

## 应用图标

```bash
./scripts/generate-app-icon.sh
./scripts/generate-app-icon.sh --check
```

`design/AppIcon/` 是唯一设计源包：SVG 保存几何、颜色与设置页命名视窗，JSON 模板保存 Icon Composer 图层、阴影和材质，同目录组合脚本只负责读取、校验、资源拆分与预览验证，并把可重建产物写入 `design/AppIcon/output/`。默认命令重新组合后只同步发生变化的 Xcode 正式资源；`--check` 不写项目资源，只检查它们是否与设计输出一致。设计预览位于 `design/AppIcon/output/Preview/`，详细边界见[应用图标设计源](../design/AppIcon/Main.md)。

所有脚本默认使用 `/Applications/Xcode.app/Contents/Developer` 和 `platform=macOS,arch=arm64`，可通过 `DEVELOPER_DIR` 与 `XCODE_DESTINATION` 覆盖。

# 新建文件技术决策

产品行为见[新建文件需求](../../Requirements/Features/NewFile.md)。Finder 菜单目标、外置卷、结果选择和权限边界分别见 [Finder 菜单语义](../Platform/Finder/ContextMenus.md)、[Finder 管理位置](../Platform/Finder/ManagedLocations.md)、[Finder 结果选择](../Platform/Finder/ResultSelection.md)和[文件访问](../Platform/FileAccess.md)。

## 模板身份与名称

每个模板以软件生成的唯一、稳定 ID 关联元数据和内部文件。菜单显示名与默认文件名均可重复，不能作为存储键、文件查找依据或跨进程命令中的模板身份。名称修改只改变对应属性，保持模板身份和内容关联。

菜单项按模板 ID 绑定用户选择，主应用按同一身份解析模板。已删除或不可读取的模板形成运行时失败，不按名称寻找替代项。这使同名模板和菜单展示后的模板删除都具有明确语义。

### 名称编辑的原生焦点边界

名称输入使用同一个窗口的原生 field editor；异步提交期间必须保留文本控件身份，才能把输入、选区和后续点击关联到正确字段。完整模板列表保留控件，名称保存期间保持列表和文件操作区稳定；写盘失败后的快照同步也保留已有清单。焦点交接在提交成功后执行，失败时继续由原控件接收输入。

名称提交与模板文件操作共享控制器的串行写入约束。文件操作会话随状态页窗口存活，切换页面不释放未完成操作的占用状态；原生编辑入口读取当前会话状态，避免仅依赖下一次 SwiftUI 更新后才生效的控件属性。操作锁与视觉反馈独立，名称只读和短操作都保持正常外观。

项目观察（2026-09-08，macOS 26.6.2、Xcode 26.6）：对已经编辑的 `NSTextField` 调用 `selectText` 恢复选择时，可能同步产生结束编辑通知。因此，程序化恢复期间仍属于当前交接，不能把该通知再次解释为用户离开字段。该时序由[会话测试](../../../Tests/ECMenuTests/Settings/StatusPage/FileTemplateNameEditingSessionTests.swift)和[隐藏窗口中的原生页面测试](../../../Tests/ECMenuTests/Settings/StatusPage/FileTemplatesPageTests.swift)覆盖；它是项目验证的平台行为，不是所有 macOS 版本的通知顺序保证。测试边界见[界面预览目标](../PreviewTarget.md)。

## 模板库持久化

模板库位于用户 Application Support 下，以当前主应用 signing identifier 隔离产品身份：

```text
~/Library/Application Support/<application-signing-identifier>/FileTemplates/
├── index.json
└── Files/
    └── <文件副本 UUID>/
        └── <导入文件名>
```

Application Support 用于应用管理的用户数据，按 bundle identifier 设置子目录符合 [Apple 的目录约定](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html)。实际根目录通过 Foundation 获取；Debug 与 Release 的身份值见[构建身份](../Delivery/BuildIdentity.md)。

`index.json` 是模板清单的唯一持久化来源，当前 `schemaVersion` 为 `2`，`templates` 按菜单顺序保存。每项的 `template` 保存模板 `id`、`displayName`、`defaultFileName`，`file` 保存独立的文件副本 `id` 和 `fileName`。内部路径由文件副本 ID 和导入文件名组成；模板名称修改不改变内部文件名。文件副本与索引作为一套业务数据备份和迁移，界面偏好及功能显示开关继续使用 UserDefaults。

主应用串行管理模板库；Finder Extension 只缓存用于菜单的模板描述，通过 IPC 请求主应用执行创建。导入和更换先完整保存全新 ID 下的文件副本，再原子替换索引；索引提交失败时继续使用原清单与内容，并清理未提交副本。更换已提交后，旧副本的清理失败只记录日志，由后续首次读取时的孤儿清理重试，不把已生效的更换报告为失败。删除先提交索引，再清理副本；删除副本清理失败时同步已提交清单并明确报告清理错误。

仅模板库根目录尚不存在时执行首次初始化，建立一个空白 TXT 模板。有效的空清单表示用户已删除全部模板，重启不补回；已有根目录中的索引缺失、损坏、版本不支持或读取失败必须报告错误，不按首次初始化覆盖已有数据。初始化、文件内容读取和索引提交的实际失败由明确存储边界返回。

模板库首次读取后在主应用内维护已提交的索引快照，设置页与 IPC 查询共享同一存储所有者。修改操作只有在索引提交成功后才发布新快照。

模板库读取失败时，设置页显示错误与重试入口；主应用仍发布当前菜单开关，并将模板菜单标记为不可用。Finder 收到该有效快照后隐藏“新建文件”菜单，其他命令的开关同步继续进行。不可用状态与用户删除全部模板形成的有效空清单分别建模，缓存与传输规则见[菜单配置](../Runtime/MenuConfiguration.md#真相源与副本)。

### 文件打开与更换

内部副本保留导入文件名及扩展名，让系统默认应用按该文件的类型打开它；默认输出文件名是独立的用户设置，不决定内部副本的打开方式。无扩展名的普通文件仍可导入，系统无法打开时由管理页报告失败。

打开入口交给外部应用的是当前已提交副本的 URL。主应用只缓存索引，每次创建都重新读取该副本的内容，因此外部应用保存后，后续创建使用更新的字节。项目不监听外部编辑过程，也不保证与外部写入重叠的读取具有事务快照语义。

每次更换生成新的文件副本 ID，保持模板 ID、名称和排序。外部应用在更换后向旧 URL 保存，不能改变新模板所引用的内容；同一索引提交同时决定模板使用哪份副本，避免文件覆盖与索引更新之间出现部分生效。

### 持久化迁移

旧 `schemaVersion: 1` 由独立迁移读取；当前索引解码器只接受版本 `2`。迁移保留模板 ID、名称、顺序和文件字节，把旧 `Files/<模板 UUID>` 复制到新的副本目录。旧格式未保存导入文件名，因此迁移使用当时的默认文件名作为内部文件名。

迁移准备好全部副本后才原子提交新索引，提交成功后清理旧文件。旧索引无效、内容缺失或提交失败时保留旧索引和旧内容并报告失败；有效的旧空清单迁移后仍为空。

## 不覆盖创建的证据边界

### SDK 契约

Xcode 26.6（17F113）附带的 macOS 26.5 SDK 将 `NSDataWritingWithoutOverwriting` 定义为防止替换既有文件的写入选项，并明确它不能与 `NSDataWritingAtomic` 组合（`NSData.h:25–27`）。该契约规定目标已经存在时不得覆盖，但没有公开 Foundation 使用的系统调用，也没有单独声明跨进程事务或任意写入中断下的 crash-atomic 保证。

### 项目设计与验证范围

创建流程从所选模板取得完整内容快照，按需求定义的顺序产生名称候选，每个候选直接交给 `Data.write(to:options: .withoutOverwriting)`，不先读取“可用文件名”再执行普通覆盖写入。系统报告目标已存在时继续下一个候选，其他错误立即结束。

[NewFileTests](../../../Tests/ECMenuTests/ContextCommands/Features/NewFile/NewFileTests.swift) 定义空模板、二进制内容、同名模板身份、候选命名、模板失效与同进程并发创建的验证。并发用例要求预先存在的文件内容不变、各次创建结果互不重名且内容完整；它只覆盖同一进程中的并发任务，不提供跨进程压力结果或 Foundation 内部原子实现的证据。产品依赖 SDK 规定的“不覆盖既有目标”结果，而不是未公开的具体实现方式。

模板导入、持久化恢复与错误状态的测试入口分别位于[模板库测试](../../../Tests/ECMenuTests/FileTemplates/FileTemplateLibraryTests.swift)和[模板控制器测试](../../../Tests/ECMenuTests/Settings/StatusPage/FileTemplateControllerTests.swift)。这些隔离测试不驱动真实 Finder，也不替代 Finder 菜单加载、点击与创建后选择的运行验收。

2026-09-08 在 macOS 26.6.2（25G83）上，上述测试覆盖的二进制内容、同名模板身份、持久化失败及并发不覆盖检查通过。真实 Finder 验收确认 TXT 子菜单可创建零字节的 `untitled.txt` 和冲突后的 `untitled_copy.txt`，并在默认文件创建中确认了自动选中。菜单截图和窗口归属的证据边界见 [Finder 菜单自动截图](../FinderMenuCapture.md#模板子菜单)。

## Finder 自动选择

单一创建结果使用空根路径的 `NSWorkspace.selectFile`，请求 Finder 在 main viewer 中选中新文件。窗口与来源选择限制由 [Finder 结果选择](../Platform/Finder/ResultSelection.md)统一说明；本功能不模拟输入，也不进入重命名模式。

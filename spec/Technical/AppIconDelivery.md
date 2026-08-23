# 应用图标交付

产品行为见[应用呈现与运行生命周期](../Requirements/Main.md#应用呈现与运行生命周期)。本文件记录 macOS 对正式应用图标的系统处理，以及项目选择 Icon Composer 的原因。

## 平台契约

Apple 的当前应用图标规范要求为 macOS 提供未预先遮罩的方形图层，最终圆角由系统统一应用。预制圆角遮罩会妨碍系统材质并可能使边缘劣化。Icon Composer 使用一个分层文档描述背景和前景，Xcode 根据目标平台、外观与尺寸生成最终应用图标；同名 `.icon` 文档会取代旧的 AppIcon Asset Catalog。

参考：

- [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

## 项目观察

项目于 2026-08-21 在 macOS 26.6.1（25G76）、Xcode 26.6（17F113）中验证：把旧式预制图标替换为有效的 Icon Composer 文档后，Xcode 会生成正确的 ICNS 和 Asset Catalog，但 Launch Services 可能继续按原 bundle identifier 与图标资源名的组合提供已经缓存的旧图标。相同构建产物使用新的测试 bundle identifier 时立即显示 Icon Composer 图标；是否静态声明 `LSUIElement` 不改变该结果。由此可以区分资源编译错误和本机登记缓存，避免为图标问题改变应用呈现生命周期。

这项观察只描述上述系统版本与本地开发构建。正式发行版本通过递增 bundle version 表达应用更新。项目内重复使用相同身份和路径的调试构建时，即使强制更新 Launch Services 登记、递增 bundle version、重启 Dock 与用户级 IconServices，后者的持久缓存仍可能返回旧位图。项目实测需要删除当前用户可重建的 IconServices store 与 Dock icon cache，再重新登记当前应用，系统才会读取新的 ICNS；项目脚本只在显式指定图标刷新模式时执行该缓存重建，不保留缓存备份。

## 项目设计

正式图标使用 `ApplicationIcon.icon` 作为 Xcode 交付入口，不与旧式 `.appiconset` 并存。设计源保持未遮罩的方形画布：背景由 Icon Composer 文档 fill 提供，波纹和指针作为彼此独立的前景图层；源矢量不包含最终圆角、外部图标阴影或平台材质。设置页透明图标从相同前景几何派生，不作为 Bundle 或 Dock 图标来源。

`design/AppIcon/` 是唯一设计源包：SVG 表达几何、颜色与设置页命名视窗，Icon Composer JSON 模板表达图层顺序和平台合成参数。同目录组合脚本只读取并校验设计源，生成被忽略且可完整重建的本地输出，通过 XML 校验透明设置图标，并通过 Icon Composer 渲染正式图标预览；项目级脚本再把其中的正式资源同步到 Xcode 固定入口。项目资源和设计输出均为派生物，不得反向作为设计源修改。

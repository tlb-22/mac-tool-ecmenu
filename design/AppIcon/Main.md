# 应用图标设计源

本目录是应用图标的唯一设计源。`AppIcon.svg` 保存几何、颜色、元素内部变换以及设置页命名视窗；`IconComposer.template.json` 保存 Icon Composer 的图层顺序、阴影与材质；`compose.sh` 读取并校验前两者，再生成完整设计输出。

```bash
./design/AppIcon/compose.sh
```

生成物位于被版本控制忽略的 `output/`：`ApplicationIcon.icon` 是正式应用图标候选产物；`Preview/ApplicationIcon-Default.png` 用于检查系统合成效果，`Preview/SettingsAppIcon.svg` 用于检查透明矢量并同步到项目设置页资源。`output/` 可以随时删除重建，不得作为设计源手工修改。

项目资源通过根级脚本同步：

```bash
./scripts/generate-app-icon.sh
./scripts/generate-app-icon.sh --check
```

默认模式重新组合并只同步发生变化的项目资源；`--check` 重新组合设计输出，但不写入 Xcode 实际资源，只检查两者是否一致。

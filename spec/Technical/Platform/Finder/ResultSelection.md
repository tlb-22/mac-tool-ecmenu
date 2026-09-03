# Finder 结果选择

通用证据范围见[平台边界](../Main.md)。本文件说明命令生成文件后，公开 API 能提供的 Finder 反馈边界。

## SDK 契约

`NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)` 会激活 Finder 并打开窗口。根路径为空字符串时在 main viewer 中选择文件；根路径非空时打开新的 file viewer；文件路径为 `nil` 时只打开根目录（macOS 26.5 SDK `NSWorkspace.h:48–50`）。

`NSWorkspace.activateFileViewerSelecting(_:)` 会激活 Finder，并打开一个或多个窗口选择给定 URL（`NSWorkspace.h:52–53`）。因此单一新文件使用空根路径的 `selectFile`，批量输出使用支持多个 URL 的 `activateFileViewerSelecting`。

## 能力限制

空根路径只指定 main viewer，不保证 Finder 不激活或不出现窗口；项目实测中 Finder 仍可能打开窗口。公开 `FIFinderSyncController` API 也没有取得菜单来源窗口身份或写回该窗口选择的接口。

因此，在不引入 Apple Events 或辅助功能 UI scripting 的前提下，自动选择结果与“绝不出现 Finder 窗口”不能同时保证。公开 API 也没有进入重命名模式的参数，本项目不做输入模拟。平台升级后应重新验收单文件与批量选择是否激活或打开新的 Finder 窗口。

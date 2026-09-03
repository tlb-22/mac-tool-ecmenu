# Finder 管理位置

通用证据范围见[平台边界](../Main.md)，文件访问授权见[文件访问边界](../FileAccess.md)。

## SDK 契约

`FIFinderSyncController.directoryURLs` 是 Extension 管理的根目录集合。Finder 对每个根及其子目录发送观察回调；Extension 每次启动都必须显式设置该集合，没有管理目录时也应设置为空集合（macOS 26.5 SDK `FinderSync.h:26–35`）。

`FileManager.mountedVolumeURLs` 枚举当前可用挂载卷，`.skipHiddenVolumes` 排除隐藏卷（`NSFileManager.h:30–38, 102–104`）。`NSWorkspace` 分别提供卷挂载、卸载和重命名通知，并在通知信息中携带卷 URL（`NSWorkspace.h:298–316`）。

## 项目观察与设计

项目观察到，只登记 `/` 时 Finder 不会在独立挂载的外置卷上提供菜单；Apple 没有承诺一个管理根会跨越挂载点。Extension 因而在启动时登记 `/` 和当前全部非隐藏卷根，并在卷挂载、卸载或重命名后重新枚举完整集合。

管理范围和访问授权是两个边界：登记卷根不代表主应用或 Extension 获得对应文件的读写权。平台升级后应重新验收启动时已经挂载的卷、新挂载卷、卷重命名以及各卷深层目录中的菜单覆盖。

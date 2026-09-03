# 构建身份

本文件是产品 Bundle ID、App Group 和签名配对的唯一文档来源。运行时对端认证见 [IPC](../Runtime/IPC.md)，Finder 登记语义见 [Extension 生命周期](../Platform/Finder/ExtensionLifecycle.md)。

## 产品配置

| 配置 | 主应用名称 | 主应用 Bundle / signing identifier | Finder Extension Bundle / signing identifier | App Group |
|---|---|---|---|---|
| Release | `ECMenu` | `com.axiomace.ecmenu` | `com.axiomace.ecmenu.finderext` | `GVPW27HJZ5.ecmenu` |
| Debug | `ECMenu(Debug)` | `com.axiomace.ecmenu.debug` | `com.axiomace.ecmenu.debug.finderext` | `GVPW27HJZ5.ecmenu.debug` |

Xcode build configuration 通过 `ECMENU_APPLICATION_NAME`、`ECMENU_APPLICATION_BUNDLE_IDENTIFIER`、`ECMENU_FINDER_EXTENSION_BUNDLE_IDENTIFIER` 和 `ECMENU_APPLICATION_GROUP_IDENTIFIER` 定义这些值。后三项还分别以 `ECMApplicationSigningIdentifier`、`ECMFinderExtensionSigningIdentifier` 和 `ECMApplicationGroupIdentifier` 注入两个产品的 `Info.plist`，App Group 同时进入双方 entitlement。

运行时代码只读取当前二进制注入的值，不通过源码条件编译或硬编码常量重新判断 Debug/Release。缺少或为空的身份配置属于构建错误，不能退化到另一套配置。

## 测试目标

非产品目标使用 `com.axiomace.ecmenu.test` 子树：

| 目标 | Bundle identifier |
|---|---|
| 主应用测试 | `com.axiomace.ecmenu.test.main` |
| Finder Extension 测试 | `com.axiomace.ecmenu.test.finderext` |
| Preview | `com.axiomace.ecmenu.test.preview` |
| IPC sender | `com.axiomace.ecmenu.test.ipcsender` |

IPC sender 是验证生产身份检查的唯一例外：产品 Bundle ID 仍属于测试子树，但本地集成构建显式把 signing identifier 覆盖为当前 Finder Extension 身份。它不嵌入或交付到产品应用。

## 签名与隔离

当前所有本地目标使用 Personal Team `GVPW27HJZ5` 的 Apple Development 自动签名。Release 面向本机使用和 GitHub 分发，不执行 Developer ID export、公证或 staple；首次运行仍由用户按 macOS 界面手动放行。发布脚本的构建与校验入口见[开发脚本](../../../scripts/Main.md#release-构建)。

不同 Bundle ID 隔离标准偏好、登录项和 Launch Services/PlugInKit 登记；不同 App Group 隔离组容器及其中的 IPC socket；配置变更通知名由主应用 signing identifier 派生。因此 Debug 与 Release 不共享偏好、配置副本或 IPC，也不能互相通过身份验证。

两个产品的 entitlement 声明当前配置的同一 App Group。双方的 Sandbox 与文件授权边界见[文件访问](../Platform/FileAccess.md)，组容器中的运行态对端认证见 [IPC](../Runtime/IPC.md)。

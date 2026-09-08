# 目标架构

**待实施设计。** 保持现有产品进程与用户行为，以业务能力组织源码，在能力内部按需要区分领域、用例、呈现和平台/持久化边界。

## 目标依赖关系

```mermaid
flowchart TB
    subgraph ext[Finder Extension 进程]
        eui[Finder 回调与 AppKit 菜单适配]
        features[各功能菜单规则<br/>不可变上下文 → 语义动作]
        replica[菜单快照副本与查询客户端]
        eui --> features
        eui --> replica
    end
    subgraph app[主应用进程]
        composition[应用 Composition<br/>构造与持有进程级对象]
        views[设置页 / 参数窗口 / 编辑会话]
        ingress[IPC 请求适配]
        usecases[能力用例<br/>协调读取、规则与写入]
        domain[领域类型与纯规则]
        ports[按能力定义的窄边界<br/>模板读取 / 文件写入 / 剪贴板等]
        adapters[平台与持久化实现]
        feedback[结果反馈 / Finder 定位 / 进度窗口]
        composition --> views
        composition --> ingress
        composition --> adapters
        views --> usecases
        ingress --> usecases
        usecases --> domain
        usecases --> ports
        adapters -.->|实现接口 / 注入闭包| ports
        usecases -->|完成结果 / 进度事实| feedback
    end
    sdk[外部 API<br/>Foundation / AppKit / ImageIO / Darwin / Security]
    adapters --> sdk
    feedback --> sdk
    eui --> sdk
    features -->|类型化请求 · 由传输层发送| ingress
```

此图表达主要依赖与结果流，不表示用例直接构造反馈窗口。运行协调器连接“用例结果 → 反馈策略”，具体平台适配由 Composition 注入；领域与规则不依赖 AppKit 控件、UserDefaults 或 socket。模板页等呈现层仍需 AppKit/SwiftUI 来维持原生交互，图省略这些视觉调用。

`ECMenuShared/Contracts` 只保存两端需一致的值和请求；`ECMenuShared/Platform` 保存确实被双方复用的系统实现。它们是源码组织边界，是否进一步成为独立 Swift module 留到依赖稳定后判断。

## 目录组织

主应用以 FileTemplates、MenuConfiguration、ApplicationSettings 等能力为入口，Finder 操作集中在 Commands；设置窗口与导航由 Settings 负责。能力内部按需要区分 Domain、Application、Persistence、Platform、Presentation；具体定义、归属判断和界面查找入口集中在[目录组织规则](DirectoryRules.md)。

## 进一步阅读

- [目录组织规则](DirectoryRules.md)：五类职责、拆分条件、依赖方向和界面代码入口。
- [模块契约与目录](Boundaries.md)：能力边界、状态所有权、跨端路径、现有文件迁移映射。
- [目标执行流](Flows.md)：新建文件、配置发布、模板操作、复制路径和图片压缩的责任调整及 API 输入/输出。
- [迁移计划](../Migration.md)：先后依赖、每阶段完成标准和验证。

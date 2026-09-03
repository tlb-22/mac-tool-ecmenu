# IPC

Finder Extension 与主应用使用 App Group 容器中的 Unix-domain socket 进行定向通信。App Group、双方精确身份和环境隔离见[构建身份](../Delivery/BuildIdentity.md)；本文件只定义运行态认证与协议语义。

## 命令投递

Finder Extension 在菜单构建时冻结上下文并准备类型化命令；用户点击时为该命令建立一条独立连接，只发送一次。每个连接先完成双向身份验证，再使用八字节大端正文长度和 JSON 正文传输 frame。

```text
Finder Extension                         主应用
       │                                   │
       │  1. 建立 App Group Unix socket     │
       ├──────────────────────────────────>│
       │                                   │
       │  2. Client 验证主应用身份           │
       │     Server 验证 Extension 身份      │
       │                                   │
       │  3. 认证就绪 ACK（空 frame）         │
       │<──────────────────────────────────┤
       │                                   │
       │  4. 命令 frame（8 字节长度 + JSON）  │
       ├──────────────────────────────────>│
       │                                   │
       │  5. 完整写入后关闭；无命令接管 ACK    │
       │                                   │
       │                     6. 解码并恢复类型化调用
       │                     7. 登记独立 Task
       │                     8. Handler 执行与反馈
```

主应用只有在验证 Extension 后才发送空的认证就绪 ACK。它保证 Client 不会在 Server 取得动态对端身份前写完并关闭，只确认认证阶段完成，不携带命令接管状态或业务结果。

命令完整写入后 Client 关闭连接，不等待接管或执行回执。协议不提供自动重试、去重、业务结果回传、提交状态查询或应用级超时；每次点击都是独立请求。完整写入只证明本次点对点发送完成，不证明主应用已经解码、恢复或执行命令。

菜单配置查询使用自己的独立连接和同一认证、framing，发送查询后读取一份配置响应。命令与配置查询不会共享响应，每个操作独占一条连接，因此都不需要请求编号。主应用收到命令后生成的本地任务 ID 只用于进程内生命周期和反馈，不进入 IPC。

Client 在连接、身份验证、认证就绪 ACK 或完整写入失败时记录错误并播放一次系统默认错误提示音。Server 对认证失败、无效 frame、无法解码的负载或未知命令只记录并关闭连接，不发送应用层错误响应。

命令请求不持久化。主应用与 Extension 成对构建和交付，因此命令信封不携带独立协议版本，也不保留旧负载兼容分支；菜单配置使用自身的当前 schema 版本，升级规则见[菜单配置](MenuConfiguration.md#状态模型)。

## 对端身份验证

macOS 26.5 SDK 为本地 socket 提供 `LOCAL_PEERTOKEN`，可从已连接端取得对端的完整 `audit_token_t`。两端在读取或发送任何业务正文前依次使用：

```text
LOCAL_PEERTOKEN
  → SecTaskCreateWithAuditToken
  → SecTaskValidateForRequirement
```

由 Lightweight Code Requirements 表达的运行态要求同时约束：

- 对端具有当前构建注入的精确 signing identifier；
- 对端 Team identifier 与验证方当前进程相同；
- 签名类别为项目使用的 Apple Development；
- 运行代码已签名且动态有效。

任一 API 失败或要求不匹配都关闭连接，不退化到 PID、进程路径、正文声明、可单独伪造的 entitlement 值或内置共享密钥。

项目在 macOS 26.6.1（25G76）、Xcode 26.6（17F113）中验证了沙箱 Extension 与非沙箱主应用之间的对称认证。`SecCodeCopyGuestWithAttributes` 路径需要读取对端磁盘代码；Extension 无权读取 `.derivedData` 中的主应用时会返回 `EPERM`，因此该路径不适合作为本项目的验证入口，也不应为开发目录增加临时权限例外。

App Group 只让沙箱 Extension 到达组容器；权限为当前用户读写的 socket 文件也不替代运行态身份验证。该通道不声称加密，也不把签名私钥泄露或系统级特权对手纳入授权保证。

## 配置变更信号

主应用通过 `DistributedNotificationCenter` 发送不携带配置正文的“可能变化”信号。任意本机进程都可以伪造该通知，但它只能促使 Extension 发起一次经过上述认证的配置拉取，不能直接改变配置或触发命令。

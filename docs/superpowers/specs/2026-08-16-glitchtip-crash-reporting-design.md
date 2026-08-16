# ShotMarker GlitchTip 崩溃上报设计

日期：2026-08-16

## 目标

在 iPhone 端接入自建 GlitchTip（Project ID 4），自动上报未捕获崩溃，并把现有 `AppLogging.error` 事件同步上报。继续保留本地 JSONL 日志，不让远端上报失败影响训练、同步或视频处理流程。

## 本期范围

- iPhone App 自动捕获未处理崩溃。
- 仅远端上报现有 `.error` 日志；`.debug`、`.info`、`.warning` 仍只保存在本地。
- Debug 和 Release 都可上报，分别标记为 `development` 和 `production`。
- 不启用性能追踪、Profiling、Session Replay 或自动 Session Tracking。
- 不接入 Watch App。watchOS 崩溃和错误上报不属于本期。
- 本期不自动上传 dSYM；发布阶段另行增加安全的手动脚本或 CI 自动化。

## 方案选择

采用 GlitchTip 官方建议的 Sentry Cocoa SDK，通过 Swift Package Manager 只链接到 `ShotMarker` iPhone target。相比自行实现 Sentry Envelope HTTP 协议，该方案能可靠捕获原生崩溃、处理离线缓存，并保持与 GlitchTip 的协议兼容。

## 组件设计

### GlitchTip 启动器

新增一个只负责 SDK 初始化的组件，在 `ShotMarkerApp.init` 最前面启动。配置包括：

- 从生成的 Info.plist 读取 `GLITCHTIP_DSN`。
- DSN 缺失或无效时保持禁用，不阻止 App 启动。
- `tracesSampleRate = 0`，不发送性能事件。
- `enableAutoSessionTracking = false`。
- `sendDefaultPii = false`。
- 根据构建配置设置 `environment`。
- 使用 SDK 默认原生崩溃处理能力。

DSN 是客户端公开地址，可以随 App 分发；GlitchTip Auth Token 绝不写入工程、App 包或 Git 历史。

### 远端错误上报器

新增轻量 `AppErrorReporting` 协议及 GlitchTip 实现。它接收已经结构化的 `AppLogEvent`，并执行以下映射：

- `name` 和 `category` 作为稳定标签。
- 统一构造 error-level SDK event，而不是把原始 `NSError.userInfo` 整体交给 SDK。
- 有 `Error` 时仅附加 error domain/code；没有 `Error` 时仍发送同类 error event。
- 事件使用 `name` 与 error domain/code 形成稳定分组，避免动态数据拆成大量 issue。
- 本期不上传 `context` 字典，避免训练记录 ID、视频 ID、任务 ID 或路径意外离开设备。
- 本期不上传原始 error description；事件正文使用代码中已经固定的业务 `message`。
- 不设置用户身份，也不附加本地日志文件、视频、训练记录或截图。

### AppLogger 集成

`AppLogger` 保持现有调用接口不变，在创建 `.error` 事件后执行两个互不依赖的出口：

1. 异步追加到现有 `AppLogStore`。
2. 交给注入的 `AppErrorReporting` 上报。

`AppLogger.shared` 使用 GlitchTip 上报器；单元测试或其他显式构造的 logger 默认使用 no-op 上报器。任何远端上报问题都不得抛回业务代码。

## 数据流

### 未捕获崩溃

1. App 启动时初始化 SDK。
2. SDK 在进程崩溃时把报告安全写入本地缓存。
3. 用户下次启动 App 时，SDK 将缓存报告发送到 `https://glitchtip.zhangrh.shop`。
4. GlitchTip 按 issue 聚合并触发项目告警。

### 已处理业务错误

1. 现有业务代码调用 `logger.error(...)`。
2. `AppLogger` 生成 `AppLogEvent`。
3. 事件继续写入本地 JSONL，同时由远端上报器发送精简错误信息。
4. 网络不可用时由 SDK 处理缓存；本地日志流程保持独立。

## 配置与发布

- 在 iPhone target 的 Debug/Release 构建配置中提供 `GLITCHTIP_DSN`，并映射到生成的 Info.plist。
- Project URL 为 `https://glitchtip.zhangrh.shop/h5/issues?project=4`；实际 SDK 端点以项目设置中复制的 DSN 为准。
- Release 已使用 `dwarf-with-dsym`。每个 Archive 都会产生新的 dSYM，后续需使用 `glitchtip-cli debug-files upload` 上传对应归档的 dSYM。
- dSYM 上传需要 Auth Token；Token 仅保存在本机环境变量或 CI Secret 中，由发布者或 CI 在每次发布时运行。

## 隐私约束

- 自动上报后，现有“只有用户主动导出才会向开发者提供诊断日志”的隐私说明不再完整。
- 上架包含该功能的版本前，需要更新公开隐私政策，并重新核对 App Store Connect 的 Crash Data 与 Other Diagnostic Data 声明。
- 远端事件不得包含视频、音频、训练记录内容、完整文件路径、HealthKit 数据或稳定用户标识。

## 测试与验收

### 自动化测试

- `.error` 同时写入本地 store 并调用一次远端 reporter。
- 其他日志级别不调用远端 reporter。
- 有 Error 与无 Error 的事件都能正确传给 reporter。
- reporter 失败或禁用时不影响本地日志。
- DSN 缺失时启动器安全跳过初始化。

### 手工验收

- 触发一条可控 `logger.error`，在 GlitchTip Project 4 中看到 error issue。
- 在不连接调试器的情况下触发测试崩溃，再次启动 App 后看到 crash issue。
- 确认事件环境、App 版本和 build 号正确。
- 确认没有 Performance/Transaction 事件。
- 上传对应 dSYM 后，确认生产崩溃堆栈完成符号化。
- 确认项目 Alert 能通过邮件或 Webhook 到达。

## 分阶段交付

1. 本期：SDK 初始化、自动崩溃、`logger.error` 上报及测试。
2. 发布准备：dSYM 上传脚本和操作说明。
3. 上架准备：隐私政策与 App Store Connect 数据声明更新。
4. 真机验收：测试错误、测试崩溃、符号化和告警链路。

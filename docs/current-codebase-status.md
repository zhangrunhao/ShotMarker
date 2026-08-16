# ShotMarker 当前项目进度

## 1. 文档元数据

- 最后更新时间：2026-08-16
- 基准分支：`main`
- 基准提交：`709350e docs: 编写项目进度状态页实施计划`
- 基准工作区：生成本次状态前无未提交改动
- 当前工程版本：iPhone App `1.1 (build 1)`；Watch App `1.1 (build 1)`
- 文档用途：项目所有者与后续 Codex 共用的当前项目状态唯一来源

本文只记录有代码、提交、实际验证结果或用户确认支持的事实。产品需求、详细设计、实施步骤和完整历史分别由 PRD、`docs/superpowers/` 与 Git 保存。

## 2. 总体状态

ShotMarker 的 iPhone 与 Apple Watch 核心训练链路已经具备：Watch 端训练打点，训练记录同步到 iPhone，iPhone 端选择视频并生成、播放和保存集锦。

当前阶段是下一次发布前的观测与隐私准备：GlitchTip 崩溃/错误上报已经接入并验证，最小埋点客户端和 Privacy Manifest 已进入仓库；按照项目所有者 2026-08-16 的确认，埋点整体工作仍在进行，完成后再统一执行真机验证、Archive、dSYM 上传和 TestFlight 发布。

仓库历史表明版本 `1.1.0` 曾完成 TestFlight 发布，但当前 App Store、TestFlight 或线上版本状态在本次任务中未重新验证，不作为当前结论。

## 3. 已完成功能

### 3.1 Watch 训练与同步

- Apple Watch 支持开始和结束训练。
- 训练中支持双击按钮和数码表冠阈值打点，并提供触觉反馈。
- Watch 端持久化训练记录并向 iPhone 发送同步 payload。
- iPhone 端支持导入记录、回传 ACK、重复 payload 幂等处理和同步诊断日志。
- iPhone 端支持训练记录列表、JSON 导入导出、选择导出和记录合并。

### 3.2 视频选择与集锦

- 支持从相册或文件选择训练视频，并校验录制时间、时长和打点覆盖范围。
- 支持准备尚未下载的视频、暂停/继续准备、不可用原因展示和临时文件清理。
- 支持多视频片段规划、重叠片段合并、边界裁剪、音频保留和打点标签叠加。
- 集锦采用持久化任务队列，支持排队、进度、取消、中断恢复、失败重试、播放和删除。
- 已完成集锦可以手动保存到相册，保存失败后可重试。
- 默认剪辑窗口为打点前 `9` 秒、打点后 `4` 秒。

### 3.3 本地日志与诊断

- `AppLogger` 将结构化日志写入本地 JSONL。
- 日志存储包含保留时间与容量清理机制。
- 用户可以导出日志及 Phone/Watch 同步诊断快照。
- 业务错误保留 error domain/code 等结构化信息。

### 3.4 GlitchTip 错误上报

- iPhone target 已集成 Sentry Apple SDK，并在 App 启动早期初始化 GlitchTip。
- SDK 原生崩溃捕获能力已接入；现有 `logger.error` 会同时保留本地日志并作为精简错误事件发送到 GlitchTip。
- 远端事件只包含允许的消息、分类、错误名称及 domain/code，不发送训练记录、视频、路径、用户身份或默认 PII。
- Debug 与 Release 分别标记 `development` 和 `production`。
- 性能追踪、Profiling、Session Replay、自动 Session Tracking 和自动 Breadcrumb 已关闭。
- 2026-08-16，项目所有者已在 GlitchTip Project 4 中确认看到“ShotMarker GlitchTip 接入验证”和多条真实业务错误事件。
- Watch App 尚未接入 GlitchTip，真机原生崩溃和符号化仍属于发布前验收项。

### 3.5 最小产品埋点

- 已定义四个固定事件：`app_launch`、`training_sync_succeeded`、`highlight_generate_succeeded`、`highlight_save_succeeded`。
- 埋点客户端向 `https://zhangrh.shop/track` 发送固定 HTTPS GET schema，不重试、不阻塞业务流程。
- 每次安装使用本地生成并持久化的 12 位随机安装标识。
- 真实埋点仅在 iPhone Release 构建启用；Debug、Watch 和其他设备形态使用 no-op 实现。
- 同步、集锦生成和保存只在成功路径记录事件，失败路径不会误记为成功。

### 3.6 Privacy Manifest

- `ShotMarker/PrivacyInfo.xcprivacy` 已加入主 App 产物。
- 已声明 Device ID 与 Product Interaction 用于 Analytics，linked 为 `true`，tracking 为 `false`。
- 已声明 UserDefaults `CA92.1` 和 File Timestamp `C617.1` 必需原因 API。
- 已有单元测试验证收集类型唯一性、用途、linked/tracking 状态和必需原因条目。

## 4. 正在进行的工作

### 4.1 埋点整体链路

ShotMarker 仓库内的最小埋点客户端、四个调用点、运行策略和 Privacy Manifest 已完成。项目所有者确认埋点工作尚未整体结束；服务端当前部署状态、数据落盘、汇总查询和生产端到端结果无法仅从本仓库确认，下一次发布前需要统一验证。

### 4.2 隐私与商店声明

- 公开隐私政策需要覆盖自动崩溃/错误上报和第一方产品分析。
- App Store Connect 需要重新核对 Crash Data、Other Diagnostic Data、Device ID 和 Product Interaction 等回答。
- Privacy Manifest 已完成代码侧声明，但不替代公开政策和 App Store Connect 人工配置。

### 4.3 发布准备

以下工作暂缓到埋点整体完成后统一执行：

- 最终发布候选的全量测试与真机验证。
- Xcode Archive 和签名检查。
- 上传与 Archive 精确匹配的 dSYM。
- TestFlight 上传与安装验证。
- 真机受控崩溃、GlitchTip 符号化与告警链路验证。

## 5. 测试与构建状态

最近一次验证日期：2026-08-16；验证基准：`709350e`。

### 5.1 全量 iPhone 测试

执行范围：`ShotMarker` scheme 的完整 `ShotMarkerTests`，目标为 iPhone 17 Pro / iOS 26.5 Simulator。

- 总计：159
- 通过：159
- 失败：0
- 跳过：0
- 结果：`** TEST SUCCEEDED **`

该结果覆盖现有训练记录、同步、视频处理、集锦任务、本地日志、GlitchTip、埋点和 Privacy Manifest 测试。它不代表真实 iPhone/Apple Watch 硬件验收。

### 5.2 Release 构建

执行无签名 `generic/platform=iOS` Release 构建：

- 结果：`** BUILD SUCCEEDED **`
- `ShotMarker.app`：已生成
- App 内 `PrivacyInfo.xcprivacy`：存在且通过 `plutil -lint`
- `ShotMarker.app.dSYM`：已生成

本次 dSYM 只是本地无签名构建的验证产物，不应代替未来正式 Archive 对应的 dSYM。

### 5.3 尚未执行的验证

- 最新代码的真实 iPhone 与 Apple Watch 联调。
- TestFlight Release 构建的真实埋点上报。
- 不连接调试器的真机受控崩溃。
- 正式 Archive dSYM 上传和崩溃堆栈符号化。
- GlitchTip 邮件或 Webhook 告警。

## 6. 风险与待确认事项

- 埋点服务端和汇总查询属于仓库外状态，本次未验证；不能仅凭客户端代码判断生产链路完成。
- GlitchTip 已验证错误事件接收，但尚未用正式 Release 真机崩溃验证原生崩溃缓存、下次启动发送和符号化。
- 正式发布若不上传匹配 dSYM，原生崩溃堆栈可能只有地址而缺少函数名与源码位置。
- 公开隐私政策与 App Store Connect 数据声明需要在包含 GlitchTip 和埋点的版本发布前更新。
- 当前 App Store 审核、线上版本和 TestFlight 可用状态未确认。
- GlitchTip 当前只覆盖 iPhone App，Watch 端崩溃不可见。
- 客户端 DSN 可以随 App 分发；GlitchTip Auth Token、Apple 凭据和证书私钥不得写入仓库。

## 7. 下一步优先级

1. 完成埋点服务端、数据落盘和汇总查询，并验证固定四事件 schema。
2. 更新公开隐私政策并准备 App Store Connect 数据声明。
3. 确定发布候选提交，重新运行全量测试和 Release 构建。
4. 使用真实 iPhone 与 Apple Watch 验证训练、同步、集锦、埋点和 GlitchTip。
5. 生成正式 Xcode Archive，上传对应 dSYM，再上传 TestFlight。
6. 从 TestFlight 安装后验证真实埋点、受控崩溃、符号化和告警。

## 8. 发布前检查项

- [x] GlitchTip SDK、DSN 和 `logger.error` 上报接入
- [x] GlitchTip 接收验证事件和业务错误事件
- [x] 四个最小埋点事件与 Release-iPhone-only 策略
- [x] App Privacy Manifest 与对应单元测试
- [ ] 埋点服务端部署及生产汇总查询验收
- [ ] 公开隐私政策更新
- [ ] App Store Connect 数据声明核对
- [ ] 发布候选全量测试与 Release 构建
- [ ] 真实 iPhone/Apple Watch 主链路验证
- [ ] 正式签名 Xcode Archive
- [ ] Archive 对应 dSYM 上传 GlitchTip
- [ ] TestFlight 上传和安装
- [ ] 真机受控崩溃、符号化与告警验收
- [ ] TestFlight 真实埋点事件与汇总结果验收

## 9. 最近进展

- 2026-08-16：`709350e` 编写项目进度状态页实施计划。
- 2026-08-16：`cbac439` 确定项目状态页的结构、事实口径和维护方式。
- 2026-08-16：`2ab1f4c` 为埋点数据和必需原因 API 增加 Privacy Manifest 声明及测试。
- 2026-08-16：`63ac371` 将真实埋点限制为 iPhone Release 构建。
- 2026-08-16：`8718a0a`、`d2c145b` 完成集锦生成、集锦保存和训练同步成功事件。
- 2026-08-16：`40c6b87` 完成最小埋点发送客户端。
- 2026-08-16：`d24d876` 启用 GlitchTip Project 4 DSN。
- 2026-08-16：`65d618c` 接入 GlitchTip 原生崩溃与 `logger.error` 上报。
- 历史里程碑：`fe24301` 记录版本 `1.1.0` 的 TestFlight 发布；当前外部状态未重新验证。

## 10. 维护规则

- 每完成一个功能或重要修复后更新本文档；纯格式或注释调整无需更新。
- 更新前确认 `main`、HEAD 和工作区状态，不覆盖未提交的用户改动。
- 代码与配置、实际测试/构建结果、已提交设计与用户确认依次作为事实来源。
- 测试结论必须注明日期、基准、范围和准确计数；专项测试不得写成全量通过。
- App Store、TestFlight、GlitchTip 和服务器部署等变化状态只有在当前任务实际验证后才能写成已确认。
- “最近进展”只保留最近 5–10 个重要节点；更早历史由 Git 保存。
- 不在本文档记录 Auth Token、Apple 登录凭据、证书私钥、真实用户数据或敏感诊断内容。

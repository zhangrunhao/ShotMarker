# ShotMarker 当前项目进度

## 1. 文档元数据

- 最后更新时间：2026-08-16
- 基准分支：`main`
- 基准客户端提交：`af44535 fix: 取消集锦任务后不再上报成功`
- 基准服务端提交：`6e1e646 test: 修正 Analytics 测试夹具类型`
- 基准工作区：更新本文档前无未提交改动
- 当前工程版本：iPhone App `1.1 (build 1)`；Watch App `1.1 (build 1)`
- 文档用途：项目所有者与后续 Codex 共用的当前项目状态唯一来源

本文只记录有代码、提交、实际验证结果或用户确认支持的事实。产品需求、详细设计、实施步骤和完整历史分别由 PRD、`docs/superpowers/` 与 Git 保存。

## 2. 总体状态

ShotMarker 的 iPhone 与 Apple Watch 核心训练链路已经具备：Watch 端训练打点，训练记录同步到 iPhone，iPhone 端选择视频并生成、播放和保存集锦。

当前阶段是下一次发布前的真机与商店验收：GlitchTip 崩溃/错误上报、ShotMarker 最小埋点客户端、Privacy Manifest、`zhangrh.shop` 的 ShotMarker 汇总查询、线上隐私政策和 Analytics 页面都已完成。2026-08-16 已在生产环境使用 1 个受控合成 `app_launch` 验证 HTTPS 204、JSONL 单条落盘、ShotMarker 聚合和 Analytics 展示；真实 Release/TestFlight 客户端上报仍未验证。

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
- 上报只包含客户端时间、固定项目名、安装标识、固定事件名和空参数对象，不包含训练、打点、视频、HealthKit、日志或错误数据。
- 训练同步在成功导入后、ACK 前上报；集锦生成仅在最终完成且任务未取消时上报；相册保存仅在照片写入与成功状态持久化都完成后上报。
- `zhangrh.shop` 汇总查询已支持 `project=shotmarker`，公开响应只返回聚合结果、查询元数据和诊断计数，不返回原始安装标识或服务器请求标识。

### 3.6 Privacy Manifest

- `ShotMarker/PrivacyInfo.xcprivacy` 已加入主 App 产物。
- 已声明 Device ID 与 Product Interaction 用于 Analytics，linked 为 `true`，tracking 为 `false`。
- 已声明 UserDefaults `CA92.1` 和 File Timestamp `C617.1` 必需原因 API。
- 已有单元测试验证收集类型唯一性、用途、linked/tracking 状态和必需原因条目。

## 4. 正在进行的工作

### 4.1 埋点生产链路

ShotMarker 客户端、四个调用点、运行策略、Privacy Manifest，以及 `zhangrh.shop` 的查询兼容、协议文档、隐私政策和 Analytics 页面均已完成并部署。生产受控请求已验证数据落盘、聚合响应脱敏和页面展示；仍需使用真实 iPhone Release/TestFlight 构建验证客户端的实际上报。生产 JSONL 中保留了本次 1 条受控合成事件。

### 4.2 隐私与商店声明

- `zhangrh.shop` 的 ShotMarker 隐私政策已覆盖第一方产品分析的客户端字段、服务器附加字段、用途、排除项和保留边界；2026-08-16 已验证线上页面与发布资源。
- 自动崩溃/错误上报的公开披露仍需在发布前复核。
- App Store Connect 需要重新核对 Crash Data、Other Diagnostic Data、Device ID 和 Product Interaction 等回答。
- Privacy Manifest 已完成代码侧声明，但不替代公开政策和 App Store Connect 人工配置。

### 4.3 发布准备

生产埋点链路已可验收，剩余发布准备为：

- 最终发布候选的全量测试与真机验证。
- Xcode Archive 和签名检查。
- 上传与 Archive 精确匹配的 dSYM。
- TestFlight 上传与安装验证。
- 真机受控崩溃、GlitchTip 符号化与告警链路验证。

## 5. 测试与构建状态

最近一次验证日期：2026-08-16；客户端验证基准：`af44535`；服务端完整检查基准：`6e1e646`，其中 ShotMarker 埋点披露最新提交为 `0141b4d`。

### 5.1 全量 iPhone 测试

执行范围：`ShotMarker` scheme 的完整 `ShotMarkerTests`，目标为 iPhone 17 Pro / iOS 26.5 Simulator。

- 总计：164
- 通过：164
- 失败：0
- 跳过：0
- 结果：`** TEST SUCCEEDED **`

该结果覆盖现有训练记录、同步、视频处理、集锦任务、本地日志、GlitchTip、埋点和 Privacy Manifest 测试。它不代表真实 iPhone/Apple Watch 硬件验收。

### 5.2 Release 构建

执行全新 DerivedData 的 `generic/platform=iOS Simulator` Release 构建：

- 结果：`** BUILD SUCCEEDED **`
- `ShotMarker.app`：已生成
- App 内 `PrivacyInfo.xcprivacy`：存在且通过 `plutil -lint`
- `ShotMarker.app.dSYM`：已生成

本次模拟器 dSYM 只是本地构建验证产物，不应代替未来正式 Archive 对应的 dSYM。

### 5.3 `zhangrh.shop` 完整检查

在 `zhangrh.shop` 执行 `npm run check`：

- Automation 测试：9/9 通过。
- Frontend 测试：142/142 通过。
- Backend 测试：26/26 通过。
- Frontend lint 与 typecheck：通过。
- Hub、Cardgame、ShotMarker 和 Analytics 构建：通过。

该结果证明仓库代码与构建通过；生产部署与线上验收证据单独记录如下。

### 5.4 `zhangrh.shop` 生产验收

2026-08-16 对生产环境执行的验证结果：

- Backend 以 `6e1e646` 发布并重建；Cardgame 健康检查与 ShotMarker 过滤查询均返回 HTTP 200。
- 使用 1 个随机合成安装标识发送 `app_launch`，HTTPS `/track` 返回 204，`events.jsonl` 从 7 条/1819 字节变为 8 条/2057 字节，且恰好新增 1 条匹配记录。
- 8 条 JSONL 均为合法 schema v1；新记录包含严格的 8 个字段、32 位十六进制服务器请求标识，参数解码后精确为空对象。
- 受控事件写入后，ShotMarker 1 日聚合为 1 个事件、1 个设备和 1 个 `app_launch`；响应中不含安装标识、服务器请求标识或原始参数。
- `https://zhangrh.shop/shotmarker/privacy` 返回 HTTP 200，线上资源包含 2026-08-16 隐私政策、第一方产品分析说明、schema v1 字段和四个事件名。
- Analytics 线上页面已验证 Hub/Cardgame/ShotMarker 项目、`1/7/30/90` 日范围中的代表组合、手动刷新和 390×844 视口；页面数据与 API 一致，390 px 宽度无水平溢出。

上述结果是验收时点快照；生产聚合数字会随新事件变化。本文档不保存受控测试的原始安装标识或请求标识。

### 5.5 尚未执行的验证

- 最新代码的真实 iPhone 与 Apple Watch 联调。
- TestFlight Release 构建的真实埋点上报。
- 不连接调试器的真机受控崩溃。
- 正式 Archive dSYM 上传和崩溃堆栈符号化。
- GlitchTip 邮件或 Webhook 告警。

## 6. 风险与待确认事项

- 埋点服务端、汇总查询、隐私政策与 Analytics 已于 2026-08-16 在生产受控验收；这是时点性外部状态，仍不代表真实 Release/TestFlight 客户端已上报。
- GlitchTip 已验证错误事件接收，但尚未用正式 Release 真机崩溃验证原生崩溃缓存、下次启动发送和符号化。
- 正式发布若不上传匹配 dSYM，原生崩溃堆栈可能只有地址而缺少函数名与源码位置。
- 公开隐私政策的线上页面已验证；App Store Connect 数据声明仍需在包含 GlitchTip 和埋点的版本发布前更新。
- 当前 App Store 审核、线上版本和 TestFlight 可用状态未确认。
- GlitchTip 当前只覆盖 iPhone App，Watch 端崩溃不可见。
- 客户端 DSN 可以随 App 分发；GlitchTip Auth Token、Apple 凭据和证书私钥不得写入仓库。

## 7. 下一步优先级

1. 核对 App Store Connect 的 Crash Data、Other Diagnostic Data、Device ID 和 Product Interaction 声明。
2. 使用真实 iPhone 与 Apple Watch 验证训练、同步、集锦、埋点和 GlitchTip。
3. 确定发布候选提交并生成正式 Xcode Archive，上传对应 dSYM，再上传 TestFlight。
4. 从 TestFlight 安装后验证真实埋点、受控崩溃、符号化和告警。

## 8. 发布前检查项

- [x] GlitchTip SDK、DSN 和 `logger.error` 上报接入
- [x] GlitchTip 接收验证事件和业务错误事件
- [x] 四个最小埋点事件与 Release-iPhone-only 策略
- [x] App Privacy Manifest 与对应单元测试
- [x] `zhangrh.shop` ShotMarker 查询兼容、协议文档与隐私政策源文件
- [x] 当前代码全量测试与模拟器 Release 构建
- [x] 埋点服务端部署及生产汇总查询验收
- [x] 线上公开隐私政策页面验收
- [x] Analytics 线上页面、项目/时间过滤与移动端布局验收
- [ ] App Store Connect 数据声明核对
- [ ] 真实 iPhone/Apple Watch 主链路验证
- [ ] 正式签名 Xcode Archive
- [ ] Archive 对应 dSYM 上传 GlitchTip
- [ ] TestFlight 上传和安装
- [ ] 真机受控崩溃、符号化与告警验收
- [ ] TestFlight 真实埋点事件与汇总结果验收

## 9. 最近进展

- 2026-08-16：以 `6e1e646` 发布 `zhangrh.shop` Backend 和 ShotMarker 隐私页，用 1 个受控 `app_launch` 完成 204、JSONL、聚合脱敏和 Analytics 线上端到端验收。
- 2026-08-16：`af44535` 修复非协作 runner 在任务取消后误报集锦生成成功的问题；客户端全量测试增至 164 项。
- 2026-08-16：`651f991`、`6342ca4`、`7ff124b` 补强相册状态持久化、安装标识并发/格式和训练同步顺序契约。
- 2026-08-16：`55413ab`、`923c747`、`0aa903d`、`0141b4d` 完成 `zhangrh.shop` 的 ShotMarker 查询兼容、隐私政策与协议披露。
- 2026-08-16：`2ab1f4c` 为埋点数据和必需原因 API 增加 Privacy Manifest 声明及测试。
- 2026-08-16：`63ac371` 将真实埋点限制为 iPhone Release 构建。
- 2026-08-16：`8718a0a`、`d2c145b` 完成集锦生成、集锦保存和训练同步成功事件。
- 2026-08-16：`40c6b87` 完成最小埋点发送客户端。
- 2026-08-16：`d24d876`、`65d618c` 完成 GlitchTip DSN、原生崩溃和 `logger.error` 接入。

## 10. 维护规则

- 每完成一个功能或重要修复后更新本文档；纯格式或注释调整无需更新。
- 更新前确认 `main`、HEAD 和工作区状态，不覆盖未提交的用户改动。
- 代码与配置、实际测试/构建结果、已提交设计与用户确认依次作为事实来源。
- 测试结论必须注明日期、基准、范围和准确计数；专项测试不得写成全量通过。
- App Store、TestFlight、GlitchTip 和服务器部署等变化状态只有在当前任务实际验证后才能写成已确认。
- “最近进展”只保留最近 5–10 个重要节点；更早历史由 Git 保存。
- 不在本文档记录 Auth Token、Apple 登录凭据、证书私钥、真实用户数据或敏感诊断内容。

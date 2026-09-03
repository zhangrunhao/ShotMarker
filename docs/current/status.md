# ShotMarker 当前状态

- 最后复核：2026-09-03
- 验证代码基线：`codex/highlight-clip-confirmation` / `babebb0`
- 工程版本：1.3（Build 3）
- 当前阶段：片段审核与逐片段确认实现、Simulator 验证已完成，等待正式 Archive、真机与上传链路验收

## 当前结论

ShotMarker 的 iPhone、Apple Watch、训练同步、视频准备、片段审核与范围调整、逐片段长期确认与同组合恢复、可预览并固化到任务的片段序数样式、集锦任务队列、本地日志、隐私清单、GlitchTip 和四类产品埋点均已进入代码。1.3 的完整 Simulator 测试与 Release 构建已通过；最近正式签名 Archive 与 Organizer Validate 仍是 1.2（Build 1）。当前主要工作是正式 Archive、真机、TestFlight、崩溃符号化、线上埋点和商店披露验收。

## 已确认事实

- 片段确认实现代码基线的完整 iPhone scheme 为 342 项、Watch scheme 为 30 项，最近一次完整通过日期为 2026-09-03。
- 1.3（Build 3）Release Simulator 构建最近一次通过日期为 2026-09-03。
- 正式签名 Archive、App/Watch dSYM UUID 对应和 Organizer Validate 最近一次通过日期仍为 2026-08-19，版本为 1.2（Build 1）。
- 2026-08-19 验证的正式 Archive 为 1.2（Build 1），不再嵌入独立 `Sentry.framework`；该次验证没有执行 TestFlight 上传。
- 集锦生成使用持久本地任务队列；生成完成后由用户手动保存到相册。
- 新任务必须经过片段审核并保存版本 1 精确片段快照；排队、重启与中断恢复不重新套用全局前后时长，旧 1.2/1.3 任务继续走兼容规划。
- 单片段确认使用独立 schema 1 本地 Store；相同训练内容与同序视频组合恢复已确认范围及保留/排除状态，其余片段按当前默认值生成且不阻止任务创建。
- 编辑器采用工作副本和写盘后发布事务；训练删除、内容替换与合并清理失效确认，清除集锦任务不删除确认记录。
- Release iPhone 会发送精简 Analytics 和 GlitchTip 数据；产品不是完全离线应用。
- 当前没有登录、账号或由 ShotMarker 提供的业务云同步。

## 已确认但未实现

[iOS 语音口令打点与技术统计](../changes/2026-07-29-ios-voice-command-marking-spec.md) 已完成设计确认，但当前代码没有语音识别、语音事件或球员统计能力。

## 主要风险

- SwiftLint 基线不是绿色：2026-08-18 检出 42 个 violation，其中 5 个 error。
- 尚未完成当前代码基线的真机回归、TestFlight 安装和 App Store 状态确认。
- 尚未完成真实 Release Analytics、真机崩溃符号化和 GlitchTip 告警验收。
- Watch 端没有独立日志导出；现有导出主要包含 iPhone 侧同步诊断。
- 当前代码基线没有 VoiceOver 验收证据；用户明确不把它作为片段审核 Change 的完成门槛。

## 下一步

为 1.3（Build 3）生成候选 Archive 或 TestFlight Build，在真机完成核心流程、Analytics、崩溃符号化、告警和隐私披露验收，并把带日期的结果更新到 [发布状态](release.md) 与 [质量状态](quality.md)。

## 详细入口

- [产品事实](product.md)
- [技术架构](architecture.md)
- [产品埋点](analytics.md)
- [质量状态](quality.md)
- [发布状态](release.md)
- [片段确认验证记录](../archive/2026-09/2026-09-03-highlight-clip-confirmation-validation.md)

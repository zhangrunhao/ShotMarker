# ShotMarker 当前状态

- 最后复核：2026-08-19
- 代码基线：main / 9d6938f
- App 版本：1.1（Build 1）
- 当前阶段：核心功能完成，等待真机与发布链路验收

## 当前结论

ShotMarker 的 iPhone、Apple Watch、训练同步、视频准备、集锦任务队列、本地日志、隐私清单、GlitchTip 和四类产品埋点均已进入代码。当前主要工作不再是补齐核心流程，而是真机 Archive、TestFlight、崩溃符号化、线上埋点和商店披露验收。

## 已确认事实

- iPhone 和 Watch 当前共 194 项测试，最近一次完整通过日期为 2026-08-19。
- Release Simulator 构建、隐私清单打包和 dSYM 生成最近一次通过日期为 2026-08-19。
- 集锦生成使用持久本地任务队列；生成完成后由用户手动保存到相册。
- Release iPhone 会发送精简 Analytics 和 GlitchTip 数据；产品不是完全离线应用。
- 当前没有登录、账号或由 ShotMarker 提供的业务云同步。

## 已确认但未实现

[iOS 语音口令打点与技术统计](../changes/2026-07-29-ios-voice-command-marking-spec.md) 已完成设计确认，但当前代码没有语音识别、语音事件或球员统计能力。

## 主要风险

- SwiftLint 基线不是绿色：2026-08-18 检出 42 个 violation，其中 5 个 error。
- 尚未完成当前代码基线的真机 Archive、TestFlight 和 App Store 状态确认。
- 尚未完成真实 Release Analytics、真机崩溃符号化和 GlitchTip 告警验收。
- Watch 端没有独立日志导出；现有导出主要包含 iPhone 侧同步诊断。

## 下一步

使用正式 Archive 或 TestFlight Build 在真机完成 Analytics、崩溃符号化、告警和隐私披露验收，并把带日期的结果更新到 [发布状态](release.md) 与 [质量状态](quality.md)。

## 详细入口

- [产品事实](product.md)
- [技术架构](architecture.md)
- [产品埋点](analytics.md)
- [质量状态](quality.md)
- [发布状态](release.md)

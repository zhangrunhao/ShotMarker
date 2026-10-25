# 2026-08-20 发布与商店验证记录

本记录保存当时已核验的历史事实；当前状态见带最后核验日期的[发布状态](../../current/release.md)。

- 2026-08-19 已生成正式签名 iOS Archive 1.2（Build 1）；主 App 与 Watch App 的二进制 UUID 均有匹配 dSYM，Archive 不再嵌入独立 Sentry framework。
- 同日 Xcode Organizer Validate 成功，日志只有准备验证和验证成功，没有 warning/error 或 Upload Symbols Failed。自动管理的上传 Build Number 为 2，本地 Archive 元数据仍为 Build 1。
- Organizer 显示任务开始前已有 1.2（Build 1）Uploaded to Apple；该任务新归档仅 Validation succeeded，没有执行上传。
- Git 历史曾记载 1.1.0 于 2026-06-16 完成 TestFlight 发布；这不作为后来可安装状态证明。
- 2026-08-20 App Store Connect iPhone Media Manager 中，1.2 的 6.9 英寸和 6.5 英寸各有 4 张截图，顺序为 01-training-records.png、02-highlight-setup.png、03-highlight-ready.png、04-highlight-completed.png。
- 截至当次核验，没有完成当前上架、TestFlight 可安装、真机完整流程、GlitchTip dSYM 上传或 App Privacy 回答的重新验证。

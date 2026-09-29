# ShotMarker 当前状态

- 最后复核：2026-09-29（新截图替换及重新送审）
- 准备阶段静态基线：`10a9f35`；截图构建包含后续 Xcode 配置调整，Archive 源码映射未独立核验
- 工程版本：1.3（Build 3）
- 当前阶段：1.3（3）已替换新截图并重新送审，后台为 Waiting for Review；审核通过后手动发布

## 当前结论

ShotMarker 已覆盖 iPhone/Watch 训练同步、视频准备、长期可编辑集锦任务、逐片段审核、序数样式、串行生成、手动保存、本地日志及精简远端观测。任务在进入审核时创建并固定训练快照；生成可停止，修改后保留旧成片。新数据世代首次启动按已确认规格清理旧本地数据，不提供迁移。

## 已验证事实

- 2026-09-29 已按用户要求准备新截图、撤回审核并替换 iPhone 5 张、iPad 3 张、Watch 1 张，继续使用 1.3（3）重新送审并查看等待审核状态。用户确认 TestFlight 的 iPhone/Watch 正常打开，并明确跳过后续验收；不将启动反馈记为完整回归通过。
- 当日截图使用当前工作副本的 Debug Simulator 全新构建，App/Watch 版本均为 1.3（3）；合成演示完成片段调整、保留/排除与 38.5 秒成片生成。没有生成新的分发 Archive。
- 2026-09-29 静态核对 App/Watch 四个配置均为 1.3（3）；工程、Info.plist 和隐私清单语法通过，五类隐私数据、三类 Required Reason API、简体中文及非豁免加密标记均与当前配置一致。
- 完整 iPhone 测试 393 项在 2026-09-10 通过，含 14 项 UI 测试，均无失败或跳过；Watch 的最近完整验证为同日 `1975784` 的 31 项通过。
- 同日当前代码 Release generic iOS Simulator 增量构建通过；App/Watch dSYM 对应、隐私清单存在、DEBUG 入口不进入产物。全新 DerivedData 构建的最近验证代码为 `1975784`。
- 连续确认时按片段身份重建编辑器、局部时间轴及媒体加载；合并片段到远处片段、跨源视频及再次打开的真实媒体 UI 回归通过。
- 专用 Simulator 的真实媒体流程验证任务创建/恢复/隔离、编辑、默认值和重置、实际播放/相册保存、主动/后台/异常退出停止、删除及数据世代升级。故障与文件边界由自动测试补充。
- 正式 App 不再使用旧任务 Manager 或组合确认 Store；训练后续删除/合并/导入与任务无级联关系。
- iPhone/Watch 当前 epoch 为 1；iPhone 使用固定 cutover ACK 丢弃旧 Watch 载荷，成功后的新数据继续保留。
- Release iPhone 会发送四个固定 Analytics 事件和 GlitchTip 错误/崩溃信息；当前没有登录、账号或业务云同步。

## 已确认但未实现

[iOS 语音口令打点与技术统计](../changes/2026-07-29-ios-voice-command-marking-spec.md) 已完成设计确认；当前没有语音识别、语音事件或球员统计能力。

## 后续与未覆盖范围

- 等待审核结果；1.3 尚未上线，最终发布保留手动操作。
- 已保存英文更新说明、产品描述和审核备注，披露升级清理范围、前台生成及远端观测；核对了商店隐私声明，截图已更新为当前界面。
- 本轮后续验收由用户明确决定跳过。完整真机回归、iPad、VoiceOver、Watch 联机升级、生产观测及最终 Archive 签名/dSYM 仍无新增通过证据。
- 本次没有新的自动测试通过结果；SwiftLint 当前数量未复核，最近记录仍为非绿色基线。

## 详细入口

- [1.3 提交计划归档](../archive/2026-09/2026-09-29-app-store-1-3-submission-plan.md)
- [Notion 1.3 提交材料](https://app.notion.com/p/3cc387d074aa808bbffae296051b2918)
- [产品事实](product.md)
- [技术架构](architecture.md)
- [产品埋点](analytics.md)
- [质量状态](quality.md)
- [发布状态](release.md)
- [任务验证记录](../archive/2026-09/2026-09-10-editable-highlight-task-validation.md)
- [连续确认预览修复验证](../archive/2026-09/2026-09-10-clip-review-navigation-validation.md)

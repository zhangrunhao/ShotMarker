# ShotMarker 文档入口

这里是 ShotMarker 文档的唯一入口。判断实现事实时，当前代码、测试、构建和当次验证优先；判断已经生效的决定、契约和政策时，以 `current` 中的明确记录为准。

## 当前事实

- [项目状态](current/status.md)：总体结论、风险和下一步
- [产品事实](current/product.md)：当前用户流程、业务规则和有效产品决定
- [技术架构](current/architecture.md)：Targets、数据流、持久化和外部集成
- [产品埋点](current/analytics.md)：事件语义、发送契约、存储和隐私边界
- [观测验证](current/observability.md)：Analytics 与 GlitchTip 最近核验的结果和未覆盖范围
- [质量状态](current/quality.md)：测试、构建、静态检查和未覆盖范围
- [发布状态](current/release.md)：版本、披露要求和外部状态

current 只保存简洁、仍然有效且有证据支持的事实和决定，不保存开发流水账。实现事实与有效决定必须明确区分；两者冲突时，同时记录决定和已经核验的实现差距。每一份 current 文档不超过 300 行，并使用稳定、无日期、简短清晰的名称；300 行规则只适用于 current，不适用于 changes 或 archive 中的 spec、plan 或其他材料。

用户在任务中明确确认的决定视为已经作出。提议、推测和未确认方案不得记录为有效决定。

ShotMarker 对外网站、支持页和 how-to 由 `zhangrh.shop` 仓库维护，不在本仓库保存副本。

## 私有事实边界

资料按内容敏感性分类，不按来源分类。版本发布、App Store / TestFlight 状态、构建与签名结果、设备型号与系统、测试和脱敏后的 Analytics / GlitchTip 验收结论均保存在本仓库。来自真机、生产服务或后台页面，不构成必须私有的理由。

如果本机存在 `docs/private.local/`，它是独立私有 Git 仓库，只保留需限制访问的账号配置、内部主机与网络、管理入口、权限、备份等运维细节。混合资料拆开保存：公开结论应能独立理解，敏感配置留在私有台账；原始日志和截图先检查内容，不能直接随验收记录搬入 Git。

公开文档必须在私有仓库不可用时仍然完整。跨仓库的每项当前事实只有一个权威来源，其他仓库只保留必要摘要或链接。密码、私钥、Token、AccessKey、Apple API Key、数据库凭据和 `.env` 实际值不进入任何文档仓库。

## 正在进行的变更

- [首页与任务入口改版方向](changes/2026-10-25-navigation-ideas.md)：首页改为任务列表，底部提供创建任务和训练记录列表入口；仅记录，尚未设计或实施
- [iOS 语音口令打点与技术统计](changes/2026-07-29-ios-voice-command-marking-spec.md)：设计已确认，尚未实现
- [视频编辑后续优化想法](changes/2026-10-23-video-editing-ideas.md)：整个视频的训练记录点管理仍待讨论，尚未设计或开发；逐段序号布局的历史材料已归档

changes 使用扁平文件：

~~~text
YYYY-MM-DD-topic-spec.md
YYYY-MM-DD-topic-plan.md
~~~

文档治理不要求每个 Change 都生成 spec 或 plan；已经生成的材料才放入 changes。spec 和 plan 应完整、无歧义，并足以支持实施和验证；是否拆分依据变更范围或内容边界，不依据行数。changes 的规则不适用于 current 或 archive。

## 历史资料

archive 保存已经结束的设计、计划、讨论、排查、发布验证和旧文档。它不是当前事实来源。

- [2026-10 归档](archive/2026-10/)：片段审核、取景、序号布局、任务编辑入口、文档与代码维护及对应验证。
- [2026-09 归档](archive/2026-09/)：独立集锦任务、连续审核、样式和 1.3 提交材料。
- [2026-08 归档](archive/2026-08/)：Analytics、日志、文档治理及旧版提交材料。
- [2026-10-25 维护验证](archive/2026-10/2026-10-25-maintenance-validation.md)：生命周期修复、组件整理及完整回归结果。
- [2026-10-25 真机追加验收](archive/2026-10/2026-10-25-maintenance-device-acceptance.md)：路径规范化修复、追加回归及限定真机验收边界。
- [2026-10-25 文档整理记录](archive/2026-10/2026-10-25-documentation-audit.md)：审计依据及从 current 移出的既有验证/外部摘要。
- [2026-10-25 文档边界调整](archive/2026-10/2026-10-25-documentation-boundaries.md)：按实际敏感性迁移发布与验收记录，并合并重复资料。
- [2026-10-27 使用分析](archive/2026-10/2026-10-27-usage-analysis.md)：App Store 活跃与留存、自建埋点回访及测试流量边界的脱敏核验。

archive 的规则只适用于 archive；其中的 spec、plan 和其他材料不受 current 的 300 行规则约束。

归档文件放入与文件日期一致的月份目录：

~~~text
archive/YYYY-MM/YYYY-MM-DD-topic.md
archive/YYYY-MM/YYYY-MM-DD-topic-spec.md
archive/YYYY-MM/YYYY-MM-DD-topic-plan.md
~~~

月份目录只在需要归档时创建，并且必须与其中每个文件名的日期前七位一致。archive 不再按 topic 或记录类型建立更深层目录。

## 维护流程

~~~text
提出变更
→ 如任务产生 spec、plan 等材料，将其保存在 changes
→ 实施与验证
→ 更新受影响的 current 文档
→ 将已有的 spec、plan 等变更材料移入对应的 archive/YYYY-MM
~~~

归档前必须先更新 current。外部服务、App Store、TestFlight 等变化状态如果没有在当前任务重新验证，必须保留最后验证日期或标为未确认。

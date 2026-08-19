# ShotMarker 文档治理规范

- 日期：2026-08-19
- 状态：已确认
- 代码基线：main / 9d6938f
- 治理依据：PROJECT_DOCUMENT_GOVERNANCE.md 1.0

## 目标

把 ShotMarker 现有文档迁移为简单、可检索、事实可信的三层结构：

~~~text
current = 当前仍然有效的事实和决定
changes = 正在讨论、准备或执行的变更
archive = 已经结束的过程、材料和历史记录
~~~

治理只调整文档和文档入口，不修改 App 功能、工程配置、外部服务或发布状态。

## 目录结构

迁移完成后的结构：

~~~text
AGENTS.md
docs/
├── README.md
├── current/
│   ├── status.md
│   ├── product.md
│   ├── architecture.md
│   ├── quality.md
│   ├── release.md
│   └── how-to/
├── changes/
│   └── 2026-07-29-ios-voice-command-marking-spec.md
└── archive/
    └── YYYY-MM-DD-topic[-spec|-plan].md
~~~

how-to 是包含 HTML、验证脚本和四个本地图片的当前用户资料包，因此保留为 current 下的一个目录；changes 和 archive 中的 Markdown 保持扁平。

## 当前文档职责

### status.md

只提供项目总体结论、当前阶段、主要风险和下一步，并链接到其余 current 文档。

### product.md

记录当前可用的 iPhone/Watch 用户流程、剪辑规则、数据行为和有效产品决定。语音口令设计必须标明“已确认但未实现”，不得描述成现有能力。

### architecture.md

记录 Targets、数据模型、持久化、WatchConnectivity、视频任务队列、日志、GlitchTip 和 Analytics 的当前架构，不保留演进流水账。

### quality.md

记录当前代码基线下有证据支持的测试、构建、隐私清单、dSYM、使用指南验证和 SwiftLint 状态，并明确未覆盖范围。

### release.md

记录当前版本与发布配置、网络与隐私披露要求、最近一次有日期的外部验证，以及当前仍未确认的 App Store、TestFlight、真机和线上状态。

## 活跃 Change

2026-07-29 的 iOS 语音口令打点与技术统计设计已确认但没有实现。它迁移为：

~~~text
docs/changes/2026-07-29-ios-voice-command-marking-spec.md
~~~

当前没有对应 plan，不创建空计划。

## 历史迁移映射

| 现有文件 | 目标文件 |
| --- | --- |
| docs/PRD.md | docs/archive/2026-06-15-product-requirements.md |
| docs/app-review-note.md | docs/archive/2026-05-20-app-review-note.md |
| docs/current-codebase-status.md | docs/archive/2026-08-16-project-status-snapshot.md |
| docs/plans/2026-05-01-shotmarker-p0-development-plan.md | docs/archive/2026-05-01-shotmarker-p0-development-plan.md |
| docs/plans/2026-05-01-watch-recording-flow-plan.md | docs/archive/2026-05-01-watch-recording-flow-plan.md |
| docs/plans/2026-05-02-watch-to-phone-sync-development-plan.md | docs/archive/2026-05-02-watch-to-phone-sync-development-plan.md |
| docs/plans/2026-05-10-log-export-p0-implementation-plan.md | docs/archive/2026-05-10-log-export-p0-implementation-plan.md |
| docs/superpowers/plans/2026-06-14-filter-unusable-videos.md | docs/archive/2026-06-14-filter-unusable-videos-plan.md |
| docs/superpowers/plans/2026-06-15-highlight-flow-refactor.md | docs/archive/2026-06-15-highlight-flow-refactor-plan.md |
| docs/superpowers/plans/2026-06-15-highlight-job-queue.md | docs/archive/2026-06-15-highlight-job-queue-plan.md |
| docs/superpowers/plans/2026-06-16-watch-crown-marker.md | docs/archive/2026-06-16-watch-crown-marker-plan.md |
| docs/superpowers/plans/2026-06-19-shotmarker-how-to-page.md | docs/archive/2026-06-19-shotmarker-how-to-page-plan.md |
| docs/superpowers/plans/2026-08-16-project-status-document.md | docs/archive/2026-08-16-project-status-document-plan.md |
| docs/superpowers/plans/2026-08-16-shotmarker-analytics-client.md | docs/archive/2026-08-16-shotmarker-analytics-client-plan.md |
| docs/superpowers/plans/2026-08-16-shotmarker-analytics-server.md | docs/archive/2026-08-16-shotmarker-analytics-server-plan.md |
| docs/superpowers/specs/2026-06-14-filter-unusable-videos-design.md | docs/archive/2026-06-14-filter-unusable-videos-spec.md |
| docs/superpowers/specs/2026-06-15-highlight-flow-refactor-design.md | docs/archive/2026-06-15-highlight-flow-refactor-spec.md |
| docs/superpowers/specs/2026-06-15-highlight-job-queue-design.md | docs/archive/2026-06-15-highlight-job-queue-spec.md |
| docs/superpowers/specs/2026-06-16-watch-crown-marker-design.md | docs/archive/2026-06-16-watch-crown-marker-spec.md |
| docs/superpowers/specs/2026-06-19-shotmarker-how-to-page-design.md | docs/archive/2026-06-19-shotmarker-how-to-page-spec.md |
| docs/superpowers/specs/2026-08-16-glitchtip-crash-reporting-design.md | docs/archive/2026-08-16-glitchtip-crash-reporting-spec.md |
| docs/superpowers/specs/2026-08-16-project-status-document-design.md | docs/archive/2026-08-16-project-status-document-spec.md |
| docs/superpowers/specs/2026-08-16-shotmarker-analytics-design.md | docs/archive/2026-08-16-shotmarker-analytics-spec.md |

本次治理 spec 和 plan 在治理完成、current 已更新且验证通过后，移动为：

~~~text
docs/archive/2026-08-19-document-governance-spec.md
docs/archive/2026-08-19-document-governance-plan.md
~~~

## AGENTS.md 规则

保留现有 main、无 worktree、保护用户未提交修改等开发规则，并将旧的单一状态页规则替换为：

- docs/README.md 是文档入口；
- docs/current 是简洁的当前事实和有效决定来源；
- 当前代码和当次验证优先于文档；
- 新 spec/plan 扁平写入 docs/changes；
- 完成并验证后先更新 current，再移动 spec/plan 到 docs/archive；
- 外部变化状态没有当次验证时必须标明最后验证日期或未确认。

## 事实基线

- main 与 origin/main 在 9d6938f 一致，治理开始时工作区干净。
- iPhone 164 项测试于 2026-08-18 在 iOS 26.5 Simulator 通过。
- Watch 30 项测试于 2026-08-18 在 watchOS 26.5 Simulator 通过。
- Release Simulator 构建、PrivacyInfo.xcprivacy 和 dSYM 于 2026-08-18 验证通过。
- 使用指南验证脚本于 2026-08-18 通过。
- SwiftLint 于 2026-08-18 返回 42 个 violation，其中 5 个 error，均为 type_body_length。
- 线上 Analytics、GlitchTip、App Store、TestFlight 和真机状态本次不重新验证，只能保留明确日期的历史事实或标为当前未确认。

## 非目标

- 不修改 Swift、Xcode 工程、配置或测试代码。
- 不改变 App Store 截图源目录。
- 不重新验证或变更外部服务。
- 不删除历史文档内容。
- 不重写归档文件中的历史路径或历史决策。

## 验收标准

- docs 顶层只有 README.md、current、changes 和 archive。
- current 包含五份简洁主题文档和完整可验证的 how-to 资料包。
- changes 只保留尚未结束的语音口令 spec。
- 所有旧 Markdown 都按映射保存在扁平 archive，没有内容丢失。
- AGENTS.md 不再引用 docs/current-codebase-status.md 或 docs/superpowers。
- 使用指南验证脚本在新路径通过。
- 当前 Markdown 内部链接全部可解析。
- git diff --check 通过，且没有 Swift、Xcode 或配置文件变更。

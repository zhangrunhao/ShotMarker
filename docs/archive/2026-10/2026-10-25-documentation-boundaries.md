# 文档公开与私有边界调整

- 日期：2026-10-25
- 范围：文档归属、去重、入口和规则；没有修改 App 代码或外部服务。
- 依据：用户要求重新判断发布、真机和观测验收记录的私有必要性，并把非敏感资料放回正常仓库。

## 归属决定

按实际内容的敏感性分类，不再按 App Store Connect、TestFlight、真机或生产后台等证据来源分类。版本、构建、签名结果、设备型号与系统、测试结论以及脱敏后的 Analytics / GlitchTip 验证结果由项目正常仓库维护。

账号配置、内部主机与网络、管理入口、权限、备份和其他需要限制访问的操作细节继续保留私有。混合记录拆分，正常仓库应有可独立理解的结论；原始日志和后台截图不随文档直接迁入。

每项当前事实只有一个权威来源。迁移保留原验证日期、证据来源、失败和未覆盖范围，不把整理日期当成新的验收日期。

## ShotMarker 迁移

本次逐项核对私有台账 `82c0b34` 中 ShotMarker 资料。移除 2 份当前资料和 11 份历史资料的私有副本；同主题已有公开记录时合并唯一内容，不另建重复档案。

| 原私有资料（文件名） | 正常仓库权威位置 |
| --- | --- |
| current/release.md | [发布状态](../../current/release.md)、[质量状态](../../current/quality.md)及下列历史记录 |
| current/observability.md | [观测验证](../../current/observability.md)、[产品埋点](../../current/analytics.md) |
| 2026-08-16-shotmarker-observability-validation.md | [观测验收](../2026-08/2026-08-16-observability-validation.md) |
| 2026-08-20-release-status.md | [1.2 发布验证](../2026-08/2026-08-20-release-status.md) |
| 2026-09-29-store-screenshot-replacement.md | [1.3 商店截图](../2026-09/2026-09-29-app-store-screenshots.md) |
| 2026-10-23-iphone-developer-install.md | [片段审核验证](2026-10-23-clip-review-validation.md) |
| 2026-10-23-clip-framing-iphone-install.md | [取景验证](2026-10-23-clip-framing-validation.md) |
| 2026-10-23-clip-editor-simplify-iphone-install.md | [编辑精简验证](2026-10-23-clip-editor-simplify-validation.md) |
| 2026-10-23-framing-priority-iphone-install.md | [取景优先级验证](2026-10-23-framing-priority-validation.md) |
| 2026-10-25-clip-number-layout-iphone-install.md | [序号布局验证](2026-10-25-clip-number-layout-validation.md) |
| 2026-10-25-editor-controls-style-iphone-install.md | [编辑控件样式验证](2026-10-25-editor-controls-style-validation.md) |
| 2026-10-25-task-entry-iphone-install.md | [任务入口验证](2026-10-25-task-entry-validation.md) |
| 2026-10-25-maintenance-device-acceptance.md | [维护后真机验收](2026-10-25-maintenance-device-acceptance.md) |

内部测试组名称未迁入；公开文档只保留其测试状态。没有迁入设备 UDID、测试者邮箱、账号定位、凭据、原始事件或后台截图。原有临时证据路径只作为历史索引，不代表文件永久可用。

私有 ShotMarker 区当前不再维护发布或观测事实，仅保留台账建立时含内部操作上下文的治理历史和本次迁移指引。旧规则中“一律私有”的归属已标为被取代，历史操作经过仍保留。

## 网站资料

同次检查将 `zhangrh.shop` 的 3 份非敏感历史资料迁回网站仓库，删除另外 3 份已有正常仓库副本的重复发布记录；具体映射和网站验证见[网站边界调整记录](https://github.com/zhangrunhao/zhangrh.shop/blob/main/docs/archive/2026-10/2026-10-25-documentation-boundaries.md)。共享服务器和敏感生产实例配置仍由私有台账维护。

## 验证范围

本次只迁移和整理文档；App Store、TestFlight、Analytics、GlitchTip 和设备连接均未重新验证。代码与工程配置未变，不重跑 iOS 构建和真机测试。

- 检查正常仓库 77 份、私有仓库 17 份现存 Markdown：197 个本地链接、22 个可对照工作区的跨仓库 GitHub 目标及 4 个标题锚点均有效。外站及无本地副本的第三方 GitHub 链接未联网验证。
- 两仓库 70 份日期归档符合月份与扁平结构；12 份 current 均不超过 300 行，最大 292 行；活跃入口没有指向已删除私有事实的链接。
- 两正常仓库的新增公开内容已检查凭据、设备标识、账号与私有配置；没有搬入原始敏感证据。三个仓库的改动均为 Markdown，文本差异检查通过。
- 网站 Node.js 24 的 212 项测试通过，具体范围见网站同主题记录；没有将这些测试算作 iOS 或线上服务验收。

# ShotMarker 质量状态

- 最后复核：2026-08-19
- 验证代码基线：main 工作区（基准提交 9d6938f）
- 最近完整测试验证：2026-08-19
- 最近 Release 构建验证：2026-08-19

## 已验证

| 范围 | 环境 | 最近验证 | 结果 |
| --- | --- | --- | --- |
| iPhone 测试 | iPhone 17 Pro / iOS 26.5 Simulator | 2026-08-19 | 164 通过，0 失败，0 跳过 |
| Watch 测试 | Apple Watch Series 11 46mm / watchOS 26.5 Simulator | 2026-08-19 | 30 通过，0 失败，0 跳过 |
| Release 构建 | generic iOS Simulator | 2026-08-19 | 成功 |
| 正式 Archive | generic iOS Device，版本 1.2（Build 1） | 2026-08-19 | 自动签名 Archive 成功，签名校验通过 |
| Archive dSYM | ShotMarker 与 ShotMarkerWatchApp | 2026-08-19 | App UUID 完全匹配；Watch 各架构 UUID 完全匹配；未嵌入独立 `Sentry.framework` |
| Organizer Validate | Xcode Organizer | 2026-08-19 | Validation succeeded，无 warning/error 或 `Upload Symbols Failed`；未执行上传 |
| Privacy Manifest | Release App 包 | 2026-08-19 | 文件存在且 plutil 校验通过 |
| Plist、entitlements、privacy manifest 源文件 | 本地静态检查 | 2026-08-19 | 全部通过 plutil |
| Git 文本检查 | git diff --check | 2026-08-19 | 通过 |

本次正式 Archive 的本地元数据是 1.2（Build 1）。Xcode 的推荐验证流程为 App Store Connect 验证提交自动管理为 Build 2；Organizer 状态日志记录 `Prepared archive for validation` 和 `Validation succeeded`。这只是验证提交，不是 TestFlight 上传。

测试覆盖训练记录、Watch 同步、视频准备和规划、集锦任务、本地日志、GlitchTip、Analytics 请求契约及 Privacy Manifest。

## 静态检查

2026-08-18 的 SwiftLint 结果不是绿色：

- 42 个 violation；
- 其中 5 个 error；
- 5 个 error 均为 type_body_length；
- 涉及 VideoClipEditingService、TrainingSessionListView、TrainingSessionHighlightView 及两个大型测试类型。

这些问题不会否定当前测试和构建结果，但在把 lint 设为自动门禁前需要建立清理计划。

## 当前未覆盖

- 没有 UI Test、快照测试或 XCTest Plan。
- 没有仓库内 CI 配置。
- 没有 iPad 功能验收；iPad destination 仍保留在工程配置中。
- 没有当前代码基线的真机完整回归。
- 没有把本次正式 Archive dSYM 上传到 GlitchTip，也没有完成服务端符号化验收。
- 没有真实 Release/TestFlight Analytics 全链路验收。
- 没有真机崩溃、GlitchTip 符号化和告警验收。
- 本次只通过 Xcode Organizer 重新验证 Archive；没有登录 App Store Connect/TestFlight 网页复核商店和测试人员状态。

## 验证规则

- 测试、构建、发布和外部服务结论必须附验证日期和基线。
- Simulator dSYM 只能证明构建配置，不代替正式 Archive dSYM。
- changing external state 没有当次验证时，只记录最后已知日期或标为未确认。
- 文档变化不应被表述为产品代码重新通过测试；代码基线未变时引用最近一次完整验证。

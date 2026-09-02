# ShotMarker 质量状态

- 最后复核：2026-09-02
- 验证代码基线：main / a5ef08f
- 最近完整测试验证：2026-09-02
- 最近 Release 构建验证：2026-09-02

## 当前结论

当前代码基线的 iPhone、Watch 完整测试与 Release Simulator 构建均在 2026-09-02 通过。片段序数样式完成了自动验证和部分 Simulator 人工验收；VoiceOver 与独立横屏选择流程由用户继续验收，不记录为已通过。SwiftLint 基线仍非绿色，真机与线上链路验收尚未完成。

## 已验证

| 范围 | 环境 | 最近验证 | 结果 |
| --- | --- | --- | --- |
| iPhone 测试 | iPhone 17 Pro / iOS 26.5 Simulator | 2026-09-02 | 189 通过，0 失败，0 跳过 |
| Watch 测试 | Apple Watch Series 11 46mm / watchOS 26.5 Simulator | 2026-09-02 | 30 通过，0 失败，0 跳过 |
| Release 构建 | generic iOS Simulator | 2026-09-02 | 成功 |
| 正式 Archive | generic iOS Device，版本 1.2（Build 1） | 2026-08-19 | 自动签名 Archive 与签名校验成功 |
| Archive dSYM | ShotMarker 与 ShotMarkerWatchApp | 2026-08-19 | 二进制 UUID 均匹配；未嵌入独立 `Sentry.framework` |
| Organizer Validate | Xcode Organizer | 2026-08-19 | Validation succeeded；未执行上传 |
| Privacy Manifest | Release App 包 | 2026-08-19 | 文件存在且 plutil 校验通过 |
| Plist、entitlements、privacy manifest 源文件 | 本地静态检查 | 2026-08-19 | 全部通过 plutil |
| Git 文本检查 | git diff --check | 2026-09-02 | 通过 |

测试覆盖训练记录、Watch 同步、视频准备和规划、片段序数模型与布局、任务样式快照和导出、集锦任务、本地日志、GlitchTip、Analytics 请求契约及 Privacy Manifest。

正式 Archive、Organizer 与线上服务的完整外部证据由私有台账维护；上表只保留理解公开质量状态所需的摘要，不据此推断当前线上状态。

## 片段序数样式人工验收

2026-09-02 在 iPhone 17 Pro / iOS 26.5 Simulator 完成并保留了以下证据：

- 无缩略图占位显示“暂时无法显示视频预览”并提供同义辅助功能文本，不作为功能错误，且不阻止生成；竖屏视频预览为静态完整画面，左右黑底填充，没有裁切或播放。
- 标识拖到四角和中心时均完整留在拟合后的视频画面内；字号 4%–16%、文字不透明度 0%–100% 和黑底不透明度 0%–100% 的独立变化可见。
- 创建任务时捕获的样式保存在任务 JSON；之后修改默认设置不会改写该任务。对应自动测试也覆盖默认设置变化后的任务快照。
- 360×640、9:16、24 fps、30 秒的导出包含合并长标签 `1–2/3` 和短标签 `3/3`，两者位置一致且完整可见；重新启动 App 后本地默认样式仍可恢复。

以下两项没有记录为已通过：

- 独立横屏视频的首项完整缩略图流程未完成手动选择验收；横竖屏坐标和边界语义已有单元测试，但不替代该人工流程。
- VoiceOver 的自定义方向操作、调节项和值域播报由用户自行验证，本次未更改辅助功能系统设置。

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
- 片段序数样式尚缺上述 VoiceOver 与独立横屏流程的用户人工验收。
- 2026-08-19 的正式 Archive dSYM 尚未上传到 GlitchTip，也没有完成服务端符号化验收。
- 没有真实 Release/TestFlight Analytics 全链路验收。
- 没有真机崩溃、GlitchTip 符号化和告警验收。
- App Store Connect 与 TestFlight 的当前可用状态尚未通过网页独立复核。

## 验证规则

- 测试、构建、发布和外部服务结论必须附验证日期和基线。
- Simulator dSYM 只能证明构建配置，不代替正式 Archive dSYM。
- 持续变化的外部状态没有当次验证时，只记录最后已知日期或标为未确认。
- 文档变化不应被表述为产品代码重新通过测试；代码基线未变时引用最近一次完整验证。

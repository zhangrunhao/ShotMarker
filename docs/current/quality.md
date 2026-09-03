# ShotMarker 质量状态

- 最后复核：2026-09-03
- 验证功能代码基线：codex/clip-confirmation / 50ebdb9
- 最近完整测试验证：2026-09-03
- 最近 Release 构建验证：2026-09-03

## 当前结论

当前代码基线的 iPhone、Watch 完整测试与 Release Simulator 构建均在 2026-09-03 通过。集锦片段审核按用户最终确认的范围完成 Simulator 验收和时间轴真实触控 UI 回归；用户明确不要求本 Change 验证 VoiceOver，因此未执行且不记录为通过。SwiftLint 基线仍非绿色，真机与线上链路验收尚未完成。

## 已验证

| 范围 | 环境 | 最近验证 | 结果 |
| --- | --- | --- | --- |
| 片段审核直接受影响测试 | iPhone 17 Pro / iOS 26.5 Simulator | 2026-09-03 | 104 通过，0 失败，0 跳过 |
| iPhone 完整测试 | iPhone 17 Pro / iOS 26.5 Simulator | 2026-09-03 | 272 通过，0 失败，0 跳过；含 4 项真实拖动 UI 测试 |
| Watch 完整测试 | Apple Watch Series 11 46mm / watchOS 26.5 Simulator | 2026-09-03 | 30 通过，0 失败，0 跳过 |
| Release 构建 | generic iOS Simulator | 2026-09-03 | 成功；App、dSYM 和 Privacy Manifest 存在，DEBUG 时间轴测试入口未进入二进制 |
| 正式 Archive | generic iOS Device，版本 1.2（Build 1） | 2026-08-19 | 自动签名 Archive 与签名校验成功 |
| Archive dSYM | ShotMarker 与 ShotMarkerWatchApp | 2026-08-19 | 二进制 UUID 均匹配；未嵌入独立 `Sentry.framework` |
| Organizer Validate | Xcode Organizer | 2026-08-19 | Validation succeeded；未执行上传 |
| Privacy Manifest | 当前 Release Simulator App 包 | 2026-09-03 | 文件存在 |
| Plist、entitlements、privacy manifest 源文件 | 本地静态检查 | 2026-08-19 | 全部通过 plutil |
| Git 文本检查 | git diff --check | 2026-09-03 | 通过 |

测试覆盖训练记录、Watch 同步、视频准备和规划、审核范围/编号/合并/媒体/播放/状态、版本化精确片段快照、时间轴真实拖动、片段序数模型与布局、导出、集锦任务、本地日志、GlitchTip、Analytics 请求契约及 Privacy Manifest。

正式 Archive、Organizer 与线上服务的完整外部证据由私有台账维护；上表只保留理解公开质量状态所需的摘要，不据此推断当前线上状态。

## 集锦片段审核验收

2026-09-02 至 2026-09-03 使用专用的 iPhone 17 Pro / iOS 26.5 Simulator 验收。媒体样本为 1280×720、60 秒、H.264/AAC 横屏视频；720×1280、30 秒、H.264/AAC 竖屏视频；以及 1280×720、30 秒、H.264 且无音轨的视频。训练样本包含可形成合并卡片的相邻打点。

- 入口、完整画幅缩略图、横竖屏黑底、`1`/`2–3` 编号、默认保留状态与旧规划初始范围一致；确认值通过 0.1 秒/timescale 600 规范化。
- 普通与合并卡片的排除、恢复、稳定身份、保留编辑、重新编号、四项实时汇总，以及调整后重叠或间隔不超过 1 秒的最终合并均通过。
- 编号和整卡入口、起止手柄、整体抓手、播放头及精调按钮满足独立语义和至少 44×44 点；4 项 XCUITest 以真实拖动分别验证只改变命名状态。
- 所有 0.5 秒精调、视频首尾/最短时长限制、范围移出固定打点参考线、训练数据不变、无自动播放、范围结束回起点及无音轨播放均通过。
- 只改序数样式会保留草稿；改变视频顺序或前后时长先确认且取消不丢草稿；有编辑时退出会确认，取消保留流程，确认返回训练详情。
- 缩略图失败注入显示占位但仍可编辑和生成；提交前移除来源会阻止保留卡片确认，排除不可用卡片后可提交其余有效卡片。
- 任务创建后改变默认设置并中断/重启，仍使用已确认范围和捕获样式；快速切换卡片或离开页面会取消旧胶片请求、停止播放并保持单一播放器。
- 最大 Dynamic Type 下图集退化为单列，汇总、状态和时间可读，关键内容没有截断，操作目标仍至少 44 点。

VoiceOver 流程未执行，也不记为已通过；用户在 2026-09-03 明确将其移出本 Change 的验收范围。

## 片段序数样式人工验收

2026-09-02 在 iPhone 17 Pro / iOS 26.5 Simulator 完成并保留了以下证据：

- 无缩略图占位显示“暂时无法显示视频预览”并提供同义辅助功能文本，不作为功能错误，且不阻止生成；竖屏视频预览为静态完整画面，左右黑底填充，没有裁切或播放。
- 标识拖到四角和中心时均完整留在拟合后的视频画面内；字号 4%–16%、文字不透明度 0%–100% 和黑底不透明度 0%–100% 的独立变化可见。
- 创建任务时捕获的样式保存在任务 JSON；之后修改默认设置不会改写该任务。对应自动测试也覆盖默认设置变化后的任务快照。
- 360×640、9:16、24 fps、30 秒的导出包含合并长标签 `1–2/3` 和短标签 `3/3`，两者位置一致且完整可见；重新启动 App 后本地默认样式仍可恢复。

本次片段审核验收补充覆盖了独立横屏与竖屏视频的首项完整缩略图流程。VoiceOver 仍没有当前代码基线的验收证据，但按用户决定不是本 Change 的完成门槛。

## 静态检查

2026-08-18 的 SwiftLint 结果不是绿色：

- 42 个 violation；
- 其中 5 个 error；
- 5 个 error 均为 type_body_length；
- 涉及 VideoClipEditingService、TrainingSessionListView、TrainingSessionHighlightView 及两个大型测试类型。

这些问题不会否定当前测试和构建结果，但在把 lint 设为自动门禁前需要建立清理计划。

2026-09-03 的 Release 构建仍报告 `HighlightClipPlaybackController` 观察者闭包缺少 Sendable 标注的并发警告；该警告不影响本次测试和构建结论，但构建并非 warning-free。

## 当前未覆盖

- 只有 4 项时间轴拖动 UI Test；没有覆盖完整生成流程的 UI Test、快照测试或 XCTest Plan。
- 没有仓库内 CI 配置。
- 没有 iPad 功能验收；iPad destination 仍保留在工程配置中。
- 没有当前代码基线的真机完整回归。
- 没有当前代码基线的 VoiceOver 验收证据；用户已明确其不是本 Change 的验收要求。
- 2026-08-19 的正式 Archive dSYM 尚未上传到 GlitchTip，也没有完成服务端符号化验收。
- 没有真实 Release/TestFlight Analytics 全链路验收。
- 没有真机崩溃、GlitchTip 符号化和告警验收。
- App Store Connect 与 TestFlight 的当前可用状态尚未通过网页独立复核。

## 验证规则

- 测试、构建、发布和外部服务结论必须附验证日期和基线。
- Simulator dSYM 只能证明构建配置，不代替正式 Archive dSYM。
- 持续变化的外部状态没有当次验证时，只记录最后已知日期或标为未确认。
- 文档变化不应被表述为产品代码重新通过测试；代码基线未变时引用最近一次完整验证。

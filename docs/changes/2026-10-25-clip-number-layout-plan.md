# 片段序号布局实施计划

> 执行使用 superpowers:subagent-driven-development / executing-plans；步骤按复核结果更新。独立文件域可并行，统一由主代理运行集成测试并处理接口。

**目标：** 落实已确认的操作列表、互斥编辑模式、逐段序号布局及连续继承，保证预览与成片一致。
**架构：** 可选 `MarkerLabelPlacement` 贯穿审核工作副本、持久化及执行快照；任务样式继续控制透明度。共享最终规划解析布局，基于输出画布显示预览并按段渲染。
**技术：** 现有 SwiftUI、AVFoundation、Core Image、XCTest；不增加依赖。
**规格：** [片段独立序号布局与操作列表](2026-10-25-clip-number-layout-spec.md)。

## 全局约束

- 取景默认开、序号默认关；序号关恢复取景；取景可单独关闭；列表收起不改变模式或滑杆。
- 同源成功连续确认且目标无保存值才继承；已有值优先；手动打开不继承。
- 不同有效序号布局不合并，完整重叠范围可重播；透明度统一由任务控制。
- 字号为成片画布短边 4%–16%，滑杆步长 1%；中心采用左上原点归一化坐标。
- 正常事务写 schema 4，读取 1/2/3/4；旧执行缺布局从其自身快照样式回退。
- 不覆盖无关未提交改动；提交使用中文类型前缀；不修改私有仓库或外部分发状态。

## 重点复核

- 混合横竖视频：标签相对最终画布，不相对当前来源。
- 当前项手动重开与迟到加载：不能带入上一段布局或覆盖当前元数据。
- 已保存值恰好等于默认：仍保留独立快照语义，之后改默认不污染该段。
- 完全透明和长编号：可操作轮廓独立存在，预览/导出边界一致。
- 新字段在旧任务及执行中的缺失/null：兼容与损坏保护不能混淆。

## Task 1：布局模型、事务与审核继承

**文件：** 新建 `ShotMarker/Models/MarkerLabelPlacement.swift`；修改 `Models/HighlightClipReview.swift`、`Models/HighlightTask.swift`、`Models/HighlightClipReviewContext.swift`、`Services/HighlightClipReviewPlanner.swift`、`Services/HighlightTaskPlanner.swift`、`Services/HighlightTaskValidation.swift`、`Services/HighlightTaskStore.swift`、`ViewModels/HighlightClipEditorViewModel.swift`、`ViewModels/HighlightClipReviewViewModel.swift`；对应单元测试。

**接口：** `MarkerLabelPlacement(fontSizeRatio: Double, normalizedCenterX: Double, normalizedCenterY: Double)`，`init(style: MarkerLabelStyle)`、`isValid`、`normalized`、`applying(to: MarkerLabelStyle) -> MarkerLabelStyle`；字段统一为 `markerLabelPlacement: MarkerLabelPlacement?`。编辑器提供 `effectiveMarkerLabelPlacement`、`setMarkerLabelPlacement(_:)`；导航新增可缺省布局载荷。`makeSummary` 增加默认值为 `.default` 的 `markerLabelStyle` 参数，真实任务必须传当前样式。

- [ ] 添加红测试：schema 4、逐段保存/重载、非法字段保护、相同/不同有效布局合并、旧执行回退。
- [ ] 实现有效布局解析、执行捕获、任务配置保留及重置，保存与 dirty 复用现有事务。
- [ ] 添加并验证同源继承、已保存值优先、手动打开/当前项重开独立、保存失败不导航、入口值回退清除 dirty。
- [ ] 运行全部 iPhone 单元测试；针对本任务独立复核并提交。

## Task 2：逐段导出与共享标签渲染

**文件：** `Services/VideoClipSegmentPlanner.swift`、`Services/VideoClipEditingService.swift`、`Services/ClipFramingVideoComposition.swift`、`Services/MarkerLabelLayout.swift`；可新增独立共享标签图像/布局文件；`ClipFramingExportTests` 与标签布局测试。

**接口：** 最终片段和媒体片段均接收可选 `markerLabelPlacement`，缺省用执行传入样式。公开给 UI 的共享方法接收文字、完整画布尺寸、`MarkerLabelStyle`，输出一致的标签图像与布局；沿用现有 `makeMarkerLabelOverlayImage`、metrics 及 `MarkerLabelLayout`，避免两套测量。

- [ ] 添加红测试：相同编号不同字号/位置导出各自生效，固定画布混合比例，透明序号不干扰取景，长编号完整可见。
- [ ] 按段解析布局并生成不可变叠加指令，图片缓存以实际图像属性为键；布局计算共用并处理超长标签。
- [ ] 运行标签/媒体导出测试，核对真实像素、音轨、取消清理；独立复核并提交。

## Task 3：操作列表与真实画布预览

**文件：** `Views/HighlightClipEditorView.swift`、`Views/HighlightClipReviewView.swift`、`Views/ClipFramingView.swift`、`ViewModels/HighlightReviewSession.swift`（按实际位置确认）；新增序号预览与操作状态文件；媒体元数据提供器；UI 测试。

**接口：** 使用 Task 1 的有效布局/设置方法与任务样式，使用 Task 2 的共享标签渲染；模式为取景/序号/无空间操作，列表展开为独立会话状态；不得混入持久化片段。

- [ ] 用当前真实媒体 UI 入口增加失败用例，证明操作列表、互斥与滑杆行为在旧版不存在。
- [ ] 实现操作列表、模式转换、禁用行为、会话内跨段保持；更新放弃和重置提示。
- [ ] 加载首个保留来源画布尺寸并隔离迟到回调；预览在同一画布适配当前来源，显示规划得到的最终序号。
- [ ] 实现画布内相对拖动、字号滑杆、透明编辑轮廓、边界和 VoiceOver 操作，播放与取景保持既有契约。
- [ ] 验证原生模式切换、折叠仍可调整、保存/重开/继承、浅深色及最大字号；独立复核并提交。

## Task 4：集成验证与文档收尾

- [ ] 运行 `xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,id=098856ED-DC0A-4AC0-BCE7-419ABA6E359F' -parallel-testing-enabled NO`，使用专用 DerivedData/结果包；所有 iPhone 单元与 UI 均应通过。
- [ ] 对最终差异做独立完整审查；修复真实问题后只重跑受影响范围，必要时补充整套回归。
- [ ] 核对实际 UI 截图和测试结果，不宣称未经本轮验证的真机、Archive、Watch 或商店状态。
- [ ] 更新 product、architecture、quality、status；将已完成规格/计划及验证记录放入 `docs/archive/2026-10/` 并修复入口。
- [ ] 检查文档链接、current 每份不超过 300 行、`git diff --check`；提交并整合回用户工作区，报告验证范围。

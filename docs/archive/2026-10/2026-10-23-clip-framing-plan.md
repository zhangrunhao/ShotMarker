# 片段取景实施计划

日期：2026-10-23
状态：已完成。实现代码 `b744efa` 的完整 iPhone suite 为 460 项通过、零失败/跳过；分项及整体独立审查通过，见[验证记录](2026-10-23-clip-framing-validation.md)。

## Goal

让个人投篮训练可以连续审核时沿用取景，手动跳转恢复各自保存值，并在成片中准确呈现同一取景。

## Architecture

以 `ClipFraming` 为唯一空间取景值。纯几何定义正向源画面坐标，审核工作副本只在确认事务中持久化；一次性导航参数承载继承。最终规划和不可变生成快照包含取景，导出逐来源处理方向、裁切与固定画布适配，最后叠加编号。

## Tech Stack

Swift 5 language mode / Xcode 27.1、SwiftUI、AVFoundation、Core Image、XCTest；不新增依赖。

## Spec

[已批准规格](2026-10-23-clip-framing-spec.md) 为需求权威。

## Global Constraints

- 不覆盖用户未提交修改；工作在 `codex/clip-framing`，保留原有数据世代和来源安全判断。
- `ClipFraming` 为 Codable、Equatable、Sendable；scale 1–4，步长 0.1；centerX/Y 使用正向画面左上原点，精度 0.00001，最后限制到合法边缘。
- 持久化 nil 和显式原画面需能撤销恢复；有效取景均为明确值，nil 与原画面合并等价。
- 只在同源保留/排除成功后传递一次临时取景。手动打开、撤销、跨源和结束不继承；仅继承不算主动修改。
- 配置必须先原子写盘再发布；失败保留工作副本，expectedRevision、来源安全、撤销与媒体加载代次保护均保留。
- schema 1 兼容读取且不因读取写盘；正常写入 schema 2；未来版本和损坏数据保护保留。
- 不同取景片段不合并，不裁掉重叠时间；编号在裁切后添加且透明编号不禁用裁切。
- 不把取景值、媒体或来源标识写入遥测或日志。不改 Watch、语音、源文件或时间轴拖动契约。
- xcodebuild 串行执行，使用专用 Simulator，关闭自动测试诊断采集；完整 iPhone 测试在最终集成阶段执行一次，任务阶段仅运行相关测试。
- 文档遵守 AGENTS.md：先更新 current，再归档本规格和计划；不虚构真机或发布证据。

## Review Focus

1. 保存失败或手动跳转串取景：编辑器/审核状态测试和 UI 连续跳转测试。
2. schema 升级覆盖旧值或漏传字段：真实文件 store、planner 转换、旧快照与撤销测试。
3. 不同取景合并截断动作：规划测试核对实际片段、编号及累加时长。
4. 方向/中心/留黑导致预览导出不一致：共享几何的手算坐标测试及彩色合成真实媒体像素验证。
5. 透明编号、跨源、异步旧加载破坏取景：真实媒体导出与现有加载中撤销 UI 回归。

### Task 1: 取景模型、持久化和最终规划

**Files:** 新增 `ShotMarker/Models/ClipFraming.swift` 和必要的纯几何文件；修改 `Models/HighlightClipReview.swift`、`Models/HighlightTask.swift`、`Services/VideoClipSegmentPlanner.swift`、`Services/HighlightClipReviewPlanner.swift`、`Services/HighlightTaskPlanner.swift`、`Services/HighlightTaskStore.swift`、`Services/HighlightTaskValidation.swift`；对应 `ShotMarkerTests` 模型、Store、Planner 测试。

**接口:** `ClipFraming.original`；`init(scale:centerX:centerY:)` 保留原始值以供持久化校验；`normalized` 返回 UI 可用规范值；`isValid` 校验有限值、合法范围与规范值；`normalizedCropRect` 给出左上原点归一化 CGRect。`ClipFramingGeometry` 提供 `uprightBounds(naturalSize:preferredTransform:)`、`aspectFitRect(sourceSize:in:)` 和实际裁切区域计算。若代码习惯需要调整命名，在报告中给出最终明确接口供后续任务消费。

- [x] 先添加失败测试：范围/精度/边缘和非有限值校验；不同取景重叠不合并，nil/原画面相等合并；实际文件 schema 1 无变化读取、成功写入 2、未来和损坏保护；旧执行快照缺字段可读。
- [x] ReviewItem 和 PersistedTaskClip 增加可选 `framing = nil`；ConfirmedHighlightSegment 和 HighlightClipSegment 增加明确 `framing = .original`。保持现有初始化调用兼容，旧 Codable 快照缺字段默认原画面。
- [x] 草稿、持久化、协调、确认执行与渲染片段转换完整传递取景。已确认安全保留项保留取景，重置清空。最终合并加入规范有效取景相等条件，保留不同取景片段的完整重叠。
- [x] Store 读取支持 1/2，只有正常写事务输出 2；更新校验器检查审核与执行取景。
- [x] 跑相关模型/Store/Planner 测试；自查 diff；提交 `feat: 增加片段取景模型与兼容存储规划`。

### Task 2: 编辑状态、连续继承与可操作预览

**Files:** `ViewModels/HighlightClipEditorViewModel.swift`、`ViewModels/HighlightClipReviewViewModel.swift`、`Models/HighlightClipReviewContext.swift`、`Views/HighlightClipEditorView.swift`、`Views/HighlightClipReviewView.swift`、`Views/HighlightClipReviewNavigationView.swift` 及它们现有所在子目录；可新建 `Views/ClipFramingView.swift` / 控件；重置全部文案所在配置视图；对应 Editor/Review/Context 单元测试和 Confirmation/MediaNavigation UI 测试。

**导航接口:** 保留手动 `.open(itemID:)`；新增 `.continueReview(itemID:sourceVideoID:framing:)`。ReviewVM 的 `makeEditorViewModel(itemID:inheritedFraming:)` 接受可选明确值，仅由核对目标 ID 和 videoID 的自动导航消费；不存全局上次取景。EditorVM 的 `effectiveFraming`、`setFraming(_:)`、`restoreOriginalFraming()` 可供 UI 使用，进入时基线用于 hasChanges 比较。

- [x] 先添加状态失败测试：同源保留/排除传递、跨源不传递、已有目标仅临时覆盖、手动保存/未保存恢复、继承不 dirty、用户恢复基线消除 dirty、保存失败不导航、撤销 nil/原画面/放大值。
- [x] 确认把规范有效取景与范围/状态同一事务保存，成功后才导航。撤销恢复完整快照；保留原有加载代次保护。
- [x] 移除顶部上一段/下一段行，保留标题和底部缩略图。预览在正向源画面有效区域缩放/平移，不能放大播放器外部留黑；使用共享几何。手势开始暂停且保持暂停。
- [x] 增加精确 0.1 倍率控件和“恢复原画面”，VoiceOver 调倍率与方向移动及边界反馈；未加载禁用取景。恢复时间与恢复取景独立。
- [x] 总览和底部缩略图应用保存取景；时间轴胶片仍为原图。相邻关系因取景不同分开时提示“取景不同，分别保留”。重置全部文案包含取景。
- [x] 更新顶部导航依赖的 UI 测试，增加通过真实界面控制倍率、手动跳转和恢复的回归。跑相关状态/界面测试，自查后提交 `feat: 支持连续审核继承取景与手动独立切换`。

### Task 3: 按片段取景导出并验证真实媒体

**Files:** `Services/VideoClipEditingService.swift`、必要的独立 `Services/ClipFramingVideoComposition.swift`、`Services/HighlightRenderRunner.swift`；`ShotMarkerTests/VideoClipEditingServiceTests.swift`、`HighlightTaskMediaIntegrationTests.swift` 和可新增 `ClipFramingExportTests.swift`。

- [x] 先写真实合成素材失败测试，以中心/边缘彩色区域核对 2× 裁切，核对旋转纵向视频和不同源方向，且编号文字及底色均为 0 时仍裁切。
- [x] 每个输出区间携带来源尺寸、preferredTransform、取景和输出时间；先方向归一化，再按共享几何裁切，适配第一保留来源正向尺寸的固定画布，最后叠加原有编号。
- [x] 避免一个 composition track 的 preferredTransform 错用于全部来源；实际输出尺寸和像素验证不同来源的方向与黑边仅来自比例适配。
- [x] 保留音轨、取消、进度、不可变执行快照和旧成片事务。核对不同取景重叠片段的实际时长。
- [x] 跑真实媒体、导出、Runner 和任务事务相关测试，自查后提交 `feat: 导出每段独立取景并保持编号布局`。

### Task 4: 集成验收、文档与归档

**Files:** 上述范围必要修复；`docs/current/product.md`、`architecture.md`、`quality.md`、`status.md`、`docs/README.md`；归档本规格、计划和新的验证记录。

- [x] 运行完整 iPhone suite：`xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,id=098856ED-DC0A-4AC0-BCE7-419ABA6E359F' -derivedDataPath /tmp/ShotMarkerFramingQA -parallel-testing-enabled NO -collect-test-diagnostics never`，保存唯一 xcresult 和日志。
- [x] 检查最大字号主操作、取景恢复和底部跳转可达；检查真实媒体截图/导出帧。VoiceOver 实机朗读若未验证必须如实记录。
- [x] 独立审查完整变更，处理重要问题并运行必要针对性回归；不要为纯格式或文档重复完整测试。
- [x] 按实测更新 current 中实现事实与质量边界，再将 spec/plan/验证记录放入 `docs/archive/2026-10/`，移除 README 的活跃取景项并链接归档。
- [x] 中文提交实现与文档；报告已完成行为和验证结果，不擅自推送远端或声称新真机验证。

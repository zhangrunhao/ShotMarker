# ShotMarker 集锦片段审核与范围调整 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有视频准备与持久化集锦任务之间加入默认合并片段审核、单片段播放与 0.1 秒范围调整，并让新任务在排队、重启和中断恢复时始终使用用户确认的精确片段快照。

**Architecture:** 保留 `VideoClipSegmentPlanner.highlightPlan` 作为旧任务兼容入口和默认审核范围的单一基线，在其旁新增无 UI 状态的 `HighlightClipReviewPlanner`，负责范围规范化、审核草稿、实时汇总、最终合并与快照验证。SwiftUI 图集、编辑器、时间轴、播放器和媒体帧加载各自放在独立文件；`HighlightJobManager` 只接受已确认片段创建版本 1 新任务，`HighlightJobRunner` 以 `clipPlanVersion` 判别新旧路径，并把同一份快照范围交给现有导出服务。

**Tech Stack:** Swift 5 language mode、SwiftUI、Combine、Photos/PhotosUI、AVFoundation/CoreMedia、UIKit、XCTest、Xcode 26.6 / Swift 6.3.3 toolchain

**Spec:** `docs/archive/2026-09/2026-09-02-highlight-clip-review-spec.md`

**执行结果（2026-09-03）：** 功能代码基线 `50ebdb9` 的 8 组直接受影响测试 104 项、完整 iPhone scheme 272 项（含 4 项真实拖动 UI 测试）及完整 Watch scheme 30 项均为 0 失败、0 跳过，generic iOS Simulator Release 构建成功。专用 iPhone 17 Pro / iOS 26.5 Simulator 使用 1280×720/60 秒横屏有声、720×1280/30 秒竖屏有声、1280×720/30 秒横屏无声样本完成约定范围验收；用户明确不要求本 Change 验证 VoiceOver，因此未执行且不记为通过。当前代码基线的真机、正式 Archive、TestFlight 与线上服务链路仍未验证。

## Global Constraints

- 实施工作在现有 linked worktree `/Users/runhaozhang/Documents/project/ShotMarker/.worktrees/clip-confirmation` 和分支 `codex/clip-confirmation` 中进行；不要再创建嵌套 worktree。每个任务开始前运行 `git branch --show-current` 和 `git status --short`，不得丢弃或覆盖用户未提交修改。
- 设计基线为 `8c549f5`，计划编写时 HEAD 为 `d392378`。基线测试记录是 iPhone 189 项、Watch 30 项通过，只能作为实施前历史证据；完成时必须记录新一轮实际计数。
- 本 Change 不修改 `MARKETING_VERSION` 或 `CURRENT_PROJECT_VERSION`；产品 target 保持 1.3（Build 3）。
- `TrainingSession`、`ShotMarkerEvent.markedAt`、Watch 同步载荷、训练 JSON 导入导出和 `ClipSettingsStore` 编码契约不得修改。审核状态只存在于本次生成流程，确认前不写磁盘。
- 默认审核单位是现有规划已合并的卡片；合并卡片整体保留、排除或调整，第一版不得拆开卡片内部单个打点，也不得重新排序或跨视频移动。
- 第一版不支持任务创建后再次编辑/重渲染、逐帧编辑、可变速播放、转场、音量、画幅裁切、捏合缩放或跨 App 恢复审核草稿；不得改变现有序数样式、音轨保留、视频方向和手动保存相册行为。
- 所有可读卡片初始保留；排除不得删除卡片、改变稳定 ID、重置范围或修改原始打点。被排除卡片恢复时沿用排除前范围。
- 统一时间语义是来源视频开头起算的 `TimeInterval`；触摸和确认值按 0.1 秒规范化，精调步长为 0.5 秒，最终导出用 timescale 600。视频至少 1 秒时最短片段为 1 秒；更短视频只能使用完整有效范围。
- 最终合并只比较图集原始顺序相邻、同一视频的保留卡片；被排除或不同视频的中间卡片会中断合并链。间隔使用规格中的对称公式，重叠或实际间隔不超过 1 秒才合并。
- 新任务必须同时保存 `clipPlanVersion = 1` 和非空、已验证的 `confirmedSegments`。1.2/1.3 旧任务两个字段均为 `nil` 时继续旧规划；任何不一致、版本 1 缺失/损坏快照或未知版本都明确失败，不能回退。
- 新任务只复制最终片段引用的临时视频。任务创建、Runner、重启、中断恢复和导出必须使用同一份精确片段；创建后修改全局前后时长或序数样式不得改写任务。
- 审核缩略图和胶片帧完整画幅显示，竖屏使用黑色填充；懒加载、可取消并有上限缓存。缩略图失败只显示占位，来源永久不可读才阻止保留状态确认。
- 图集编号、卡片、起止手柄、整体抓手、播放游标和全部 0.5 秒操作必须提供独立辅助功能语义；触控区域至少 44×44 点，最大 Dynamic Type 时图集退化为单列。
- 不新增 Analytics 事件、远端字段或业务上传。日志只能记录计数、时长、是否合并和错误类别，不得记录文件名、Photos local identifier、训练/打点 UUID、帧、音视频内容或用户标识。
- 工程使用 `PBXFileSystemSynchronizedRootGroup`；把新 `.swift`/fixture 文件放入现有 `ShotMarker/` 或 `ShotMarkerTests/` 目录即可进入 target，不手工编辑 PBX file reference。
- 每个实现提交使用中文 Conventional Commit 备注，例如 `feat: 增加片段审核规划`、`fix: 固化确认片段任务快照`、`test: 补充片段审核回归测试`、`docs: 更新片段审核当前事实并归档变更`。
- 完成后先用 fresh evidence 更新受影响的 `docs/current/`，确保每份不超过 300 行，再把本 spec 与 plan 移入 `docs/archive/2026-09/`。

## File Map

### Create

- `ShotMarker/Models/HighlightClipReview.swift`：审核范围、打点引用、卡片、草稿、汇总、确认快照和输入指纹等纯值类型。
- `ShotMarker/Models/HighlightClipTimeline.swift`：局部窗口、屏幕坐标映射和四类时间轴动作。
- `ShotMarker/Services/HighlightClipReviewPlanner.swift`：统一 0.1 秒规则、范围编辑、默认草稿、重新编号、最终合并、汇总和快照验证。
- `ShotMarker/Services/HighlightClipReviewMediaProvider.swift`：当前选择视频的 AVAsset 解析、卡片中点缩略图、局部胶片帧、取消和有上限缓存。
- `ShotMarker/ViewModels/HighlightClipReviewViewModel.swift`：审核草稿、排除/恢复、范围变更、汇总、缩略图状态、不可用状态、提交状态和草稿失效判断。
- `ShotMarker/ViewModels/HighlightClipPlaybackController.swift`：单一活跃播放器、范围播放、游标预览、结束回起点和观察者清理。
- `ShotMarker/Views/HighlightClipReviewView.swift`：双列/单列图集、卡片、实时汇总、错误和“确认并生成”。
- `ShotMarker/Views/HighlightClipEditorView.swift`：播放预览、时间值、局部时间轴、0.5 秒精调、保留状态与恢复默认。
- `ShotMarker/Views/HighlightClipTimelineView.swift`：胶片帧、固定打点线、选区、两个边界手柄、整体抓手和独立播放游标。
- `ShotMarkerTests/HighlightClipReviewPlannerTests.swift`：默认草稿、范围、重新编号、最终合并、汇总和快照验证。
- `ShotMarkerTests/HighlightClipReviewViewModelTests.swift`：状态转换、草稿保留/失效、媒体失败和提交门槛。
- `ShotMarkerTests/HighlightClipReviewMediaProviderTests.swift`：中点/均匀采样、缓存键、缓存上限和取消。
- `ShotMarkerTests/HighlightClipPlaybackControllerTests.swift`：播放器范围、结束行为、预览和资源清理。
- `ShotMarkerTests/HighlightClipTimelineTests.swift`：局部窗口、边界转移、坐标与手势映射。
- `ShotMarkerTests/Fixtures/HighlightJob-1.3.json`：含现有 1.3 `ClipSettings.markerLabelStyle`、但不含两个新字段的旧任务 fixture。

### Modify

- `ShotMarker/Services/VideoClipSegmentPlanner.swift:18-76,135-241`：让导出片段保留全部关联 marker ID，并让默认审核草稿复用现有匹配和初次合并结果。
- `ShotMarker/Models/HighlightJob.swift:3-59`：加入两个可选判别/快照字段和兼容编码键。
- `ShotMarker/ViewModels/HighlightJobManager.swift:95-131,275-292`：强制新任务接收已确认片段、验证、过滤来源视频并固化版本 1。
- `ShotMarker/Services/HighlightJobRunner.swift:4-138`：按版本解析新旧片段，拒绝损坏数据，并把精确范围交给导出。
- `ShotMarker/Services/VideoClipEditingService.swift:18-43,215-331`：适配保留全部 marker ID 的导出片段，不改变实际起止时间、音轨、方向和标签样式。
- `ShotMarker/Views/TrainingSessionHighlightView.swift:8-118,155-232,657-788`：改为审核入口，保存/失效审核草稿，协调退出提示和使用确认快照创建任务。
- `ShotMarkerTests/VideoClipSegmentPlannerTests.swift:27-256`：更新片段构造并验证初次合并保留全部打点。
- `ShotMarkerTests/HighlightJobStoreTests.swift:24-141`：新旧任务 JSON 往返和 1.2/1.3 缺字段兼容。
- `ShotMarkerTests/HighlightJobManagerTests.swift:33-230,377-464`：版本 1 创建、只复制引用视频、设置快照和重启测试。
- `ShotMarkerTests/HighlightJobRunnerTests.swift:19-126`：新旧分支、错误矩阵和精确范围传递。
- `ShotMarkerTests/VideoClipEditingServiceTests.swift:40-356`：更新关联打点构造并保留现有导出回归。
- `docs/README.md`、`docs/current/product.md`、`docs/current/architecture.md`、`docs/current/quality.md`、`docs/current/status.md`：完成验证后更新当前事实和 Change 状态。

### Archive after verified completion

- `docs/archive/2026-09/2026-09-02-highlight-clip-review-spec.md`
- `docs/archive/2026-09/2026-09-02-highlight-clip-review-plan.md`

---

### Task 1: 建立审核值类型与统一时间范围规则

**Files:**

- Create: `ShotMarker/Models/HighlightClipReview.swift`
- Create: `ShotMarker/Services/HighlightClipReviewPlanner.swift`
- Create: `ShotMarkerTests/HighlightClipReviewPlannerTests.swift`

**Interfaces:**

- Produces: `HighlightClipRange(start:duration:)`, `end`
- Produces: `HighlightClipMarkerReference(id:markedAt:timeInVideo:originalMatchedNumber:)`
- Produces: `HighlightClipReviewItem(id:videoID:markerReferences:defaultStart:defaultDuration:start:duration:isIncluded:)`
- Produces: `ConfirmedHighlightSegment(id:videoID:markerIDs:start:duration:markerNumberLowerBound:markerNumberUpperBound:markerTotalCount:)`
- Produces: `HighlightClipReviewDraft(selectedVideoCount:totalMarkerCount:items:)`
- Produces: `HighlightClipReviewSummary(includedMarkerCount:excludedMarkerCount:finalSegments:displayNumberRangesByItemID:mergingItemIDs:)`
- Produces: `HighlightClipRangeEdit.setStart`, `.setEnd`, `.moveBy`, `.replace`
- Produces: `HighlightClipReviewPlanner.normalizedTenths(_:)`, `apply(_:to:videoDuration:)`, `validatedRange(_:videoDuration:)`

- [ ] **Step 1: Write failing canonical-time and range-edit tests**

Create `ShotMarkerTests/HighlightClipReviewPlannerTests.swift` with the shared fixture helper and these first tests:

```swift
@testable import ShotMarker
import XCTest

final class HighlightClipReviewPlannerTests: XCTestCase {
    func testNormalizedTenthsUsesSixHundredTimescaleAndNearestTenth() {
        XCTAssertEqual(HighlightClipReviewPlanner.normalizedTenths(10.04), 10.0)
        XCTAssertEqual(HighlightClipReviewPlanner.normalizedTenths(10.06), 10.1)
        XCTAssertEqual(HighlightClipReviewPlanner.exportTimescale, 600)
    }

    func testMovingRangeClampsAtBothVideoEdgesAndKeepsLength() throws {
        let item = makeItem(start: 2, duration: 4)

        let movedEarlier = try HighlightClipReviewPlanner.apply(
            .moveBy(-20),
            to: item,
            videoDuration: 12,
        )
        let movedLater = try HighlightClipReviewPlanner.apply(
            .moveBy(20),
            to: item,
            videoDuration: 12,
        )

        XCTAssertEqual(HighlightClipRange(start: movedEarlier.start, duration: movedEarlier.duration),
                       HighlightClipRange(start: 0, duration: 4))
        XCTAssertEqual(HighlightClipRange(start: movedLater.start, duration: movedLater.duration),
                       HighlightClipRange(start: 8, duration: 4))
    }

    func testHandlesStopAtMinimumDurationWithoutCrossing() throws {
        let item = makeItem(start: 2, duration: 4)

        let movedStart = try HighlightClipReviewPlanner.apply(
            .setStart(10),
            to: item,
            videoDuration: 12,
        )
        let movedEnd = try HighlightClipReviewPlanner.apply(
            .setEnd(2),
            to: item,
            videoDuration: 12,
        )

        XCTAssertEqual(movedStart.start, 5)
        XCTAssertEqual(movedStart.duration, 1)
        XCTAssertEqual(movedEnd.start, 2)
        XCTAssertEqual(movedEnd.duration, 1)
    }

    func testShortVideoCanOnlyUseItsCompleteRange() throws {
        let item = makeItem(start: 0, duration: 0.6)

        let edited = try HighlightClipReviewPlanner.apply(
            .replace(start: 0.2, duration: 0.2),
            to: item,
            videoDuration: 0.6,
        )

        XCTAssertEqual(edited.start, 0)
        XCTAssertEqual(edited.duration, 0.6)
    }

    func testRangeMayMoveAwayFromMarkerWithoutMutatingReference() throws {
        let item = makeItem(start: 8, duration: 4)

        let edited = try HighlightClipReviewPlanner.apply(
            .moveBy(15),
            to: item,
            videoDuration: 30,
        )

        XCTAssertEqual(edited.range, HighlightClipRange(start: 23, duration: 4))
        XCTAssertEqual(edited.markerReferences, item.markerReferences)
        XCTAssertFalse(
            (edited.range.start ... edited.range.end).contains(edited.markerReferences[0].timeInVideo),
        )
    }

    func testValidatedRangeRejectsNonFiniteZeroAndOutOfBoundsValues() {
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validatedRange(
                HighlightClipRange(start: .nan, duration: 1),
                videoDuration: 10,
            ),
        )
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validatedRange(
                HighlightClipRange(start: 0, duration: 0),
                videoDuration: 10,
            ),
        )
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validatedRange(
                HighlightClipRange(start: 9.5, duration: 1),
                videoDuration: 10,
            ),
        )
    }

    private func makeItem(start: TimeInterval, duration: TimeInterval) -> HighlightClipReviewItem {
        HighlightClipReviewItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000050001")!,
            videoID: "video",
            markerReferences: [
                HighlightClipMarkerReference(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000050101")!,
                    markedAt: Date(timeIntervalSince1970: 120),
                    timeInVideo: 20,
                    originalMatchedNumber: 1,
                ),
            ],
            defaultStart: start,
            defaultDuration: duration,
            start: start,
            duration: duration,
            isIncluded: true,
        )
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails because the review models and planner do not exist.

- [ ] **Step 3: Add the exact review domain model**

Create `ShotMarker/Models/HighlightClipReview.swift` with these stored fields and computed values; keep every type free of `AVAsset`, `AVPlayer`, image data and persistence side effects:

```swift
import Foundation

struct HighlightClipRange: Equatable {
    let start: TimeInterval
    let duration: TimeInterval

    var end: TimeInterval { start + duration }
}

struct HighlightClipMarkerReference: Identifiable, Equatable {
    let id: UUID
    let markedAt: Date
    let timeInVideo: TimeInterval
    let originalMatchedNumber: Int
}

struct HighlightClipReviewItem: Identifiable, Equatable {
    let id: UUID
    let videoID: String
    let markerReferences: [HighlightClipMarkerReference]
    let defaultStart: TimeInterval
    let defaultDuration: TimeInterval
    var start: TimeInterval
    var duration: TimeInterval
    var isIncluded: Bool

    var range: HighlightClipRange { HighlightClipRange(start: start, duration: duration) }
    var defaultRange: HighlightClipRange {
        HighlightClipRange(start: defaultStart, duration: defaultDuration)
    }
    var originalNumberRange: ClosedRange<Int>? {
        guard let first = markerReferences.first, let last = markerReferences.last else { return nil }
        return first.originalMatchedNumber ... last.originalMatchedNumber
    }
}

struct ConfirmedHighlightSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let videoID: String
    let markerIDs: [UUID]
    let start: TimeInterval
    let duration: TimeInterval
    let markerNumberLowerBound: Int
    let markerNumberUpperBound: Int
    let markerTotalCount: Int
}

struct HighlightClipReviewDraft: Equatable {
    let selectedVideoCount: Int
    let totalMarkerCount: Int
    var items: [HighlightClipReviewItem]

    var matchedMarkerCount: Int { items.reduce(0) { $0 + $1.markerReferences.count } }
    var unmatchedMarkerCount: Int { totalMarkerCount - matchedMarkerCount }
}

struct HighlightClipReviewSummary: Equatable {
    let includedMarkerCount: Int
    let excludedMarkerCount: Int
    let finalSegments: [ConfirmedHighlightSegment]
    let displayNumberRangesByItemID: [UUID: ClosedRange<Int>]
    let mergingItemIDs: Set<UUID>

    var finalSegmentCount: Int { finalSegments.count }
    var totalDuration: TimeInterval { finalSegments.reduce(0) { $0 + $1.duration } }
}

enum HighlightClipRangeEdit: Equatable {
    case setStart(TimeInterval)
    case setEnd(TimeInterval)
    case moveBy(TimeInterval)
    case replace(start: TimeInterval, duration: TimeInterval)
}

struct HighlightClipReviewInputFingerprint: Equatable {
    let videos: [SelectedTrainingVideo]
    let secondsBeforeMarker: TimeInterval
    let secondsAfterMarker: TimeInterval
}
```

Do not make `ConfirmedHighlightSegment` validate or normalize in `init`; corrupted JSON must still decode so the Runner can report an explicit task-data error instead of turning a decode failure into an empty store.

- [ ] **Step 4: Implement the canonical time and edit rules**

Create `ShotMarker/Services/HighlightClipReviewPlanner.swift`. Use CoreMedia ticks as the sole 0.1-second implementation:

```swift
import CoreMedia
import Foundation

enum HighlightClipReviewPlanner {
    static let exportTimescale: CMTimeScale = 600
    private static let tenthSecondTicks: CMTimeValue = 60
    static let mergeGapTolerance: TimeInterval = 1

    static func normalizedTenths(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return seconds }
        let time = CMTime(seconds: seconds, preferredTimescale: exportTimescale)
        let tenths = (Double(time.value) / Double(tenthSecondTicks)).rounded(.toNearestOrAwayFromZero)
        return CMTime(
            value: CMTimeValue(tenths) * tenthSecondTicks,
            timescale: exportTimescale,
        ).seconds
    }

    static func validatedRange(
        _ range: HighlightClipRange,
        videoDuration: TimeInterval,
    ) throws -> HighlightClipRange {
        guard videoDuration.isFinite, videoDuration > 0,
              range.start.isFinite, range.duration.isFinite,
              range.start >= 0, range.duration > 0,
              range.end <= videoDuration,
              range.duration >= min(1, videoDuration)
        else { throw HighlightClipReviewPlanningError.invalidRange }
        return range
    }
}

enum HighlightClipReviewPlanningError: LocalizedError, Equatable {
    case emptySelection
    case sourceVideoMissing
    case invalidRange
    case missingMarkers
    case inconsistentNumbering
    case duplicateIdentity

    var errorDescription: String? {
        switch self {
        case .emptySelection: "至少需要保留一个可用片段。"
        case .sourceVideoMissing: "找不到片段使用的视频，请重新选择视频。"
        case .invalidRange: "片段范围无效，请恢复默认范围后再试。"
        case .missingMarkers: "片段缺少关联打点，请重新创建任务。"
        case .inconsistentNumbering: "片段编号数据无效，请重新创建任务。"
        case .duplicateIdentity: "片段数据重复，请重新创建任务。"
        }
    }
}
```

Implement `apply(_:to:videoDuration:)` with these exact semantics:

- normalize every incoming edit value through `normalizedTenths`;
- `.setStart` keeps the previous end fixed and clamps start to `0 ... end - minimumDuration`;
- `.setEnd` keeps start fixed and clamps end to `start + minimumDuration ... videoDuration`;
- `.moveBy` keeps duration fixed and clamps start to `0 ... videoDuration - duration`;
- `.replace` normalizes both bounds, clamps them inside the video and enforces the minimum duration;
- when `videoDuration < 1`, every edit returns `start = 0`, `duration = videoDuration`;
- no edit checks marker containment or mutates `markerReferences`; fixed references may legitimately end outside the selected range;
- throw `.invalidRange` for non-finite values or non-positive video duration; never silently convert corruption to zero.

- [ ] **Step 5: Run the focused tests and commit**

Run the Task 1 focused command again. Expected: all six tests pass.

```bash
git add \
  ShotMarker/Models/HighlightClipReview.swift \
  ShotMarker/Services/HighlightClipReviewPlanner.swift \
  ShotMarkerTests/HighlightClipReviewPlannerTests.swift
git commit -m "feat: 建立片段审核范围模型"
```

---

### Task 2: 从旧规划生成审核草稿并完成最终合并

**Files:**

- Modify: `ShotMarker/Services/VideoClipSegmentPlanner.swift:18-76,135-241`
- Modify: `ShotMarker/Services/HighlightClipReviewPlanner.swift`
- Modify: `ShotMarkerTests/VideoClipSegmentPlannerTests.swift:27-256`
- Modify: `ShotMarkerTests/HighlightClipReviewPlannerTests.swift`

**Interfaces:**

- Changes: `HighlightClipSegment.markerIDs: [UUID]` replaces the lossy single `markerID`/`markerAt` export-only fields
- Produces: `HighlightClipReviewPlanner.makeDraft(for:videos:clipSettings:) -> HighlightClipReviewDraft`
- Produces: `HighlightClipReviewPlanner.makeSummary(items:videos:) throws -> HighlightClipReviewSummary`
- Produces: `HighlightClipReviewPlanner.validateConfirmedSegments(_:videos:validMarkerIDs:) throws -> [ConfirmedHighlightSegment]`
- Produces: `ConfirmedHighlightSegment.highlightClipSegment: HighlightClipSegment`
- Preserves: `VideoClipSegmentPlanner.highlightPlan(for:videos:clipSettings:)` for legacy tasks

- [ ] **Step 1: Add failing tests for marker association and default equivalence**

Update the existing merged-segment assertions in `VideoClipSegmentPlannerTests` so a merged segment contains both ordered IDs:

```swift
XCTAssertEqual(plan.segments.first?.markerIDs, [firstMarker.id, secondMarker.id])
XCTAssertEqual(plan.segments.first?.markerNumberRange, 1 ... 2)
```

Append these tests to `HighlightClipReviewPlannerTests`:

```swift
func testDefaultDraftReusesLegacyRangesSelectionOrderAndMergedMarkerReferences() throws {
    let first = marker(id: 0x201, at: 110)
    let second = marker(id: 0x202, at: 114)
    let unmatched = marker(id: 0x203, at: 500)
    let session = TrainingSession(
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 520),
        events: [unmatched, second, first],
    )
    let preferredVideo = SelectedTrainingVideo(
        id: "preferred", recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60,
    )
    let overlappingVideo = SelectedTrainingVideo(
        id: "overlap", recordedStartAt: Date(timeIntervalSince1970: 90), duration: 90,
    )
    let settings = ClipSettings(secondsBeforeMarker: 6, secondsAfterMarker: 2)

    let legacy = VideoClipSegmentPlanner.highlightPlan(
        for: session, videos: [preferredVideo, overlappingVideo], clipSettings: settings,
    )
    let draft = HighlightClipReviewPlanner.makeDraft(
        for: session, videos: [preferredVideo, overlappingVideo], clipSettings: settings,
    )

    XCTAssertEqual(draft.totalMarkerCount, 3)
    XCTAssertEqual(draft.matchedMarkerCount, 2)
    XCTAssertEqual(draft.unmatchedMarkerCount, 1)
    XCTAssertEqual(draft.items.count, legacy.segments.count)
    XCTAssertEqual(draft.items.map(\.videoID), legacy.segments.map(\.videoID))
    XCTAssertEqual(draft.items.map(\.range), legacy.segments.map {
        HighlightClipRange(start: $0.start, duration: $0.duration)
    })
    XCTAssertEqual(draft.items.first?.markerReferences.map(\.id), [first.id, second.id])
    XCTAssertEqual(draft.items.first?.markerReferences.map(\.originalMatchedNumber), [1, 2])
    XCTAssertTrue(draft.items.allSatisfy(\.isIncluded))
}

func testExcludedCardKeepsOriginalIdentityWhileIncludedCardsRenumber() throws {
    var items = [
        makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 2),
        makeItem(idSuffix: 2, markerNumbers: [2, 3], start: 5, duration: 2),
        makeItem(idSuffix: 3, markerNumbers: [4], start: 10, duration: 2),
    ]
    items[1].isIncluded = false

    let summary = try HighlightClipReviewPlanner.makeSummary(
        items: items,
        videos: [SelectedTrainingVideo(id: "video", recordedStartAt: .distantPast, duration: 30)],
    )

    XCTAssertEqual(summary.includedMarkerCount, 2)
    XCTAssertEqual(summary.excludedMarkerCount, 2)
    XCTAssertEqual(summary.displayNumberRangesByItemID[items[0].id], 1 ... 1)
    XCTAssertEqual(summary.displayNumberRangesByItemID[items[1].id], 2 ... 3)
    XCTAssertEqual(summary.displayNumberRangesByItemID[items[2].id], 2 ... 2)
    XCTAssertEqual(summary.finalSegments.map(\.markerIDs), [
        items[0].markerReferences.map(\.id),
        items[2].markerReferences.map(\.id),
    ])
}

func testFinalMergeUsesSymmetricGapForReversedEditedRanges() throws {
    let first = makeItem(idSuffix: 1, markerNumbers: [1], start: 10, duration: 2)
    let second = makeItem(idSuffix: 2, markerNumbers: [2], start: 5, duration: 4)

    let summary = try HighlightClipReviewPlanner.makeSummary(
        items: [first, second],
        videos: [SelectedTrainingVideo(id: "video", recordedStartAt: .distantPast, duration: 30)],
    )

    XCTAssertEqual(summary.finalSegments.count, 1)
    XCTAssertEqual(summary.finalSegments[0].start, 5)
    XCTAssertEqual(summary.finalSegments[0].duration, 7)
    XCTAssertEqual(summary.mergingItemIDs, [first.id, second.id])
}

func testExcludedMiddleCardBreaksTheFinalMergeChain() throws {
    let first = makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 4)
    var middle = makeItem(idSuffix: 2, markerNumbers: [2], start: 20, duration: 2)
    let third = makeItem(idSuffix: 3, markerNumbers: [3], start: 3, duration: 4)
    middle.isIncluded = false

    let summary = try HighlightClipReviewPlanner.makeSummary(
        items: [first, middle, third],
        videos: [SelectedTrainingVideo(id: "video", recordedStartAt: .distantPast, duration: 30)],
    )

    XCTAssertEqual(summary.finalSegments.count, 2)
    XCTAssertTrue(summary.mergingItemIDs.isEmpty)
}
```

Add deterministic `marker(id:at:)` and `makeItem(idSuffix:markerNumbers:start:duration:videoID:)` helpers that derive UUIDs from fixed strings, produce ordered marker references, and default `videoID` to `"video"`. Do not use random IDs in planner tests.

Use these exact helpers:

```swift
private func marker(id: Int, at timestamp: TimeInterval) -> ShotMarkerEvent {
    ShotMarkerEvent(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
        markedAt: Date(timeIntervalSince1970: timestamp),
    )
}

private func makeItem(
    idSuffix: Int,
    markerNumbers: [Int],
    start: TimeInterval,
    duration: TimeInterval,
    videoID: String = "video",
) -> HighlightClipReviewItem {
    let references = markerNumbers.map { number in
        HighlightClipMarkerReference(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    50_000 + idSuffix * 100 + number,
                ),
            )!,
            markedAt: Date(timeIntervalSince1970: 100 + Double(number)),
            timeInVideo: Double(number),
            originalMatchedNumber: number,
        )
    }
    return HighlightClipReviewItem(
        id: UUID(
            uuidString: String(format: "00000000-0000-0000-0000-%012d", 60_000 + idSuffix),
        )!,
        videoID: videoID,
        markerReferences: references,
        defaultStart: start,
        defaultDuration: duration,
        start: start,
        duration: duration,
        isIncluded: true,
    )
}
```

- [ ] **Step 2: Add the rest of the required planner matrix before implementation**

Add these exact named cases to the same test file, with fixed inputs and direct assertions:

- `testDefaultDraftUsesOnlyMatchedMarkersAndNumbersThemContinuously`: events at 110, 500 and 130; one 100–160 video; assert references are the 110/130 events numbered 1/2.
- `testFinalMergeJoinsExactlyOneSecondGap`: ranges 0–2 and 3–5 on one video; assert one 0–5 result.
- `testFinalMergeDoesNotJoinGapGreaterThanOneSecond`: ranges 0–2 and 3.1–5.1; assert two results.
- `testFinalMergeDoesNotJoinDifferentVideos`: touching ranges on `video-a` and `video-b`; assert two results.
- `testFinalMergeUnionsThreeCardsAndAllMarkerIDs`: three adjacent cards with marker counts 1, 2 and 1; assert one segment, four ordered IDs, number bounds 1...4 and total 4.
- `testSummaryDurationUsesMergedUnionWithoutDoubleCounting`: ranges 0–4 and 2–6; assert `totalDuration == 6`, not 8.
- `testSummaryRepresentsNoIncludedItemsWithoutFinalSegments`: exclude every item; assert included 0, excluded count matches all marker refs, final array is empty, duration is 0 and original display ranges remain available.
- `testValidateConfirmedSegmentsRejectsMissingVideo`: a valid-looking snapshot references `missing`; pass the expected marker-ID set and assert `.sourceVideoMissing`.
- `testValidateConfirmedSegmentsRejectsNonFiniteAndNonTenthRanges`: test `.nan` and start `1.05`; assert `.invalidRange` for each.
- `testValidateConfirmedSegmentsRejectsEmptyMarkersDuplicateIDsAndBadNumbering`: separately assert `.missingMarkers`, `.duplicateIdentity` and `.inconsistentNumbering`.
- `testValidateConfirmedSegmentsRejectsMarkerOutsideTrainingSet`: pass a snapshot marker not present in `validMarkerIDs` and assert `.missingMarkers`.
- `testValidateConfirmedSegmentsAcceptsShortVideoOnlyForFullRange`: video duration 0.6; accept 0/0.6 and reject 0.1/0.5.

- [ ] **Step 3: Run focused tests and verify the new behavior fails**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: failures mention missing `markerIDs`, `makeDraft`, `makeSummary` and validation APIs.

- [ ] **Step 4: Preserve all marker IDs in the legacy export segment**

In `VideoClipSegmentPlanner.swift`, replace `HighlightClipSegment.markerID` and `markerAt` with `markerIDs: [UUID]`. Keep `videoID`, range and numbering fields. Single-marker construction uses `[event.id]`; `merged(with:)` concatenates `markerIDs` in plan order while taking the union range. `coveredMarkerCount` returns `markerIDs.count`, and `markerLabel` retains current `n/total` / `n-m/total` text.

Update existing test constructors and `VideoClipEditingServiceTests` fixtures to pass `markerIDs: [id]`; no production code may infer marker count only from a numeric label after this task.

- [ ] **Step 5: Implement draft generation from the legacy plan**

Add `makeDraft` to `HighlightClipReviewPlanner`:

1. Call `VideoClipSegmentPlanner.highlightPlan` exactly once with the supplied session, video order and settings.
2. Build `eventsByID` from the session and `videosByID` from the selected videos.
3. For each legacy segment, map every ordered `markerID` to a `HighlightClipMarkerReference`; `timeInVideo` is `markedAt.timeIntervalSince(video.recordedStartAt)`.
4. Derive `originalMatchedNumber` from each legacy segment’s number range; do not number unmatched events.
5. Use the first marker ID as the stable card `id`, copy the exact legacy start/duration into both default and current range, and set `isIncluded = true`.
6. Return total/selected counts even when no item can be generated so the existing coverage error remains available.

- [ ] **Step 6: Implement summary, renumbering, merge hints and validation**

`makeSummary` must iterate the original `items` array rather than sorting by edited time:

1. Validate unique item IDs, marker IDs, video IDs and ranges; normalize retained bounds to tenths.
2. Assign included marker numbers continuously in card/ref order. After rejecting empty marker references, excluded cards receive the unwrapped `originalNumberRange` in `displayNumberRangesByItemID`.
3. Build one `ConfirmedHighlightSegment` per included card with the card ID and normalized range.
4. Merge only when the immediately previous original card is included, has the same video ID, and the symmetric gap is at most one second:

```swift
let gap = max(0, max(lhs.start, rhs.start) - min(lhs.start + lhs.duration, rhs.start + rhs.duration))
```

5. A merge takes the union range, concatenates ordered marker IDs, carries the first card ID, and expands number bounds. Add every participating card ID to `mergingItemIDs`.
6. Return included/excluded marker counts and final segments; total duration is computed from merged results.

`validateConfirmedSegments(_:videos:validMarkerIDs:)` must reject an empty array, duplicate IDs within the segment-ID set, duplicate IDs within the marker-ID set, marker IDs outside the supplied training set, missing videos, non-finite/out-of-bounds/non-tenth ranges, empty marker arrays, non-contiguous bounds, per-segment marker-count mismatch or inconsistent totals. A segment ID may intentionally equal its first marker ID, so do not compare the two identity domains against each other. Numbering starts at 1, every next lower bound equals the previous upper bound + 1, and every segment’s total equals the unique marker count across the array. It returns the unchanged validated array; validation must never silently renumber or repair persisted corruption.

Add `ConfirmedHighlightSegment.highlightClipSegment` that copies exact range, marker IDs and numbering into the non-Codable export DTO.

- [ ] **Step 7: Run both focused suites and commit**

Expected: both suites pass, including all pre-existing legacy planner cases.

```bash
git add \
  ShotMarker/Models/HighlightClipReview.swift \
  ShotMarker/Services/HighlightClipReviewPlanner.swift \
  ShotMarker/Services/VideoClipSegmentPlanner.swift \
  ShotMarkerTests/HighlightClipReviewPlannerTests.swift \
  ShotMarkerTests/VideoClipSegmentPlannerTests.swift \
  ShotMarkerTests/VideoClipEditingServiceTests.swift
git commit -m "feat: 增加片段审核规划"
```

---

### Task 3: 为 HighlightJob 增加版本化精确片段快照

**Files:**

- Modify: `ShotMarker/Models/HighlightJob.swift:3-59`
- Create: `ShotMarkerTests/Fixtures/HighlightJob-1.3.json`
- Modify: `ShotMarkerTests/HighlightJobStoreTests.swift:24-141`

**Interfaces:**

- Produces: `HighlightJob.clipPlanVersion: Int?`
- Produces: `HighlightJob.confirmedSegments: [ConfirmedHighlightSegment]?`
- Preserves: absent 1.2/1.3 fields decode as `nil`; legacy re-encoding does not fabricate version 1

- [ ] **Step 1: Add failing new/legacy JSON tests**

Extend `HighlightJobStoreTests` with:

```swift
func testVersionOneJobRoundTripKeepsExactConfirmedSegments() throws {
    let segment = ConfirmedHighlightSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000060001")!,
        videoID: "photo-asset-id",
        markerIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000010101")!],
        start: 12.3,
        duration: 4.5,
        markerNumberLowerBound: 1,
        markerNumberUpperBound: 1,
        markerTotalCount: 1,
    )
    var job = try makeJob(status: .interrupted)
    job.clipPlanVersion = 1
    job.confirmedSegments = [segment]
    let fileURL = temporaryDirectory.appendingPathComponent("highlight-jobs.json")
    let store = HighlightJobStore(fileURL: fileURL)

    try store.saveJobs([job])
    let loaded = try XCTUnwrap(store.loadJobs().first)

    XCTAssertEqual(loaded.clipPlanVersion, 1)
    XCTAssertEqual(loaded.confirmedSegments, [segment])
}

func testVersion12AndVersion13FixturesDecodeWithoutClipSnapshot() throws {
    for fixture in ["HighlightJob-1.2.json", "HighlightJob-1.3.json"] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixture)")
        let job = try XCTUnwrap(HighlightJobStore(fileURL: url).loadJobs().first)

        XCTAssertNil(job.clipPlanVersion, fixture)
        XCTAssertNil(job.confirmedSegments, fixture)
    }
}

func testLegacyEncodingDoesNotInventVersionOrConfirmedSegments() throws {
    let job = try makeJob(status: .interrupted)
    let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any],
    )

    XCTAssertNil(object["clipPlanVersion"])
    XCTAssertNil(object["confirmedSegments"])
}

func testMalformedConfirmedSegmentsDecodesAsInvalidRunnerSentinel() throws {
    var object = try XCTUnwrap(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(try makeJob(status: .interrupted)),
        ) as? [String: Any],
    )
    object["clipPlanVersion"] = 1
    object["confirmedSegments"] = "damaged"
    let data = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(HighlightJob.self, from: data)

    XCTAssertEqual(decoded.clipPlanVersion, 1)
    XCTAssertEqual(decoded.confirmedSegments, [])
}
```

Update `testJobEncodingUsesExpectedTopLevelKeys` so a legacy job still expects the old key set, and add a version 1 assertion that the two new keys are present.

- [ ] **Step 2: Add the exact 1.3 compatibility fixture**

Create `ShotMarkerTests/Fixtures/HighlightJob-1.3.json` by copying the current 1.2 fixture structure, retaining the same deterministic IDs and adding the current nested default marker style:

```json
"markerLabelStyle": {
  "fontSizeRatio": 0.1,
  "normalizedCenterX": 0.15,
  "normalizedCenterY": 0.1,
  "textOpacity": 1,
  "backgroundOpacity": 0.6
}
```

Do not add `clipPlanVersion` or `confirmedSegments`; the fixture represents a task created by the already shipped 1.3 code.

- [ ] **Step 3: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightJobStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `HighlightJob` has no snapshot fields.

- [ ] **Step 4: Add optional fields without changing old decode behavior**

In `HighlightJob.swift`, add defaulted optional stored properties immediately after `clipSettings`:

```swift
var clipPlanVersion: Int? = nil
var confirmedSegments: [ConfirmedHighlightSegment]? = nil
```

Add both `CodingKeys`. In the custom encoder use `encodeIfPresent` for these two fields only; keep all existing field encoding unchanged.

Implement an explicit `init(from:)` for all current keys. Decode every existing field and `clipPlanVersion` with its normal strict type. For `confirmedSegments` only:

- missing key or JSON `null` -> `nil`;
- a valid array, including `[]` -> decoded array;
- a present but structurally invalid value/item -> `[]` as an internal invalid-data sentinel.

The sentinel does not repair or accept damage: the Runner’s version 1 branch rejects it with the actionable snapshot error. This special handling prevents one damaged new task from being silently treated as legacy or disappearing before Runner validation; wrong types for all pre-existing fields and for `clipPlanVersion` continue to throw decoding errors.

Update test factories only where a version 1 job is intended; default helper output must remain a legacy job.

- [ ] **Step 5: Run the store suite and commit**

Expected: all store tests pass, including both compatibility fixtures and the malformed-snapshot sentinel.

```bash
git add \
  ShotMarker/Models/HighlightJob.swift \
  ShotMarkerTests/HighlightJobStoreTests.swift \
  ShotMarkerTests/Fixtures/HighlightJob-1.3.json
git commit -m "feat: 增加已确认片段任务快照"
```

---

### Task 4: 让任务创建和 Runner 使用确认快照并兼容旧任务

**Files:**

- Modify: `ShotMarker/ViewModels/HighlightJobManager.swift:95-131,275-292`
- Modify: `ShotMarker/Services/HighlightJobRunner.swift:4-138`
- Modify: `ShotMarker/Services/VideoClipEditingService.swift:18-43,215-331`
- Modify: `ShotMarkerTests/HighlightJobManagerTests.swift:33-230,377-464`
- Modify: `ShotMarkerTests/HighlightJobRunnerTests.swift:19-126`
- Modify: `ShotMarkerTests/VideoClipEditingServiceTests.swift:40-356`

**Interfaces:**

- Changes: `HighlightJobManager.createJob(session:selectedVideos:clipSettings:confirmedSegments:)`
- Produces: `HighlightJobClipPlanError` with explicit inconsistent/missing/unknown-version messages
- Produces: `HighlightJobRunner` version routing that returns exact `[HighlightClipSegment]`
- Preserves: legacy `VideoClipSegmentPlanner.highlightPlan` only for jobs whose two new fields are both `nil`
- Preserves: existing `VideoClipEditingService.makeHighlightClip` range, audio, direction, marker-style and progress behavior

- [ ] **Step 1: Update manager tests to require confirmed segments**

Add a deterministic helper to `HighlightJobManagerTests` and pass it to every new-task `createJob` call:

```swift
private func makeConfirmedSegments(
    videoID: String = "photo-asset-id",
    markerID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000040101")!,
) -> [ConfirmedHighlightSegment] {
    [
        ConfirmedHighlightSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000040201")!,
            videoID: videoID,
            markerIDs: [markerID],
            start: 10,
            duration: 13,
            markerNumberLowerBound: 1,
            markerNumberUpperBound: 1,
            markerTotalCount: 1,
        ),
    ]
}

private func makeIdleManager() -> HighlightJobManager {
    HighlightJobManager(
        store: InMemoryHighlightJobStore(),
        fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
        runnerFactory: { _ in .immediateCompleted },
    )
}
```

Add these failing assertions:

```swift
func testCreateJobPersistsVersionOneAndValidatedSnapshot() async throws {
    let segments = makeConfirmedSegments()
    let manager = makeIdleManager()

    let job = try await manager.createJob(
        session: makeSession(),
        selectedVideos: [makeSelectedVideo()],
        clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
        confirmedSegments: segments,
    )

    XCTAssertEqual(job.clipPlanVersion, 1)
    XCTAssertEqual(job.confirmedSegments, segments)
}

func testCreateJobKeepsOnlyVideosReferencedByConfirmedSegments() async throws {
    let retainedURL = temporaryDirectory.appendingPathComponent("retained.mov")
    let excludedURL = temporaryDirectory.appendingPathComponent("excluded.mov")
    try Data([1]).write(to: retainedURL)
    try Data([2]).write(to: excludedURL)
    let manager = makeIdleManager()

    let job = try await manager.createJob(
        session: makeSession(),
        selectedVideos: [
            SelectedTrainingVideo(
                id: retainedURL.absoluteString,
                recordedStartAt: Date(timeIntervalSince1970: 2_000),
                duration: 900,
            ),
            SelectedTrainingVideo(
                id: excludedURL.absoluteString,
                recordedStartAt: Date(timeIntervalSince1970: 2_000),
                duration: 900,
            ),
        ],
        clipSettings: .default,
        confirmedSegments: makeConfirmedSegments(videoID: retainedURL.absoluteString),
    )

    XCTAssertEqual(job.selectedVideos.map(\.id), [retainedURL.absoluteString])
    XCTAssertTrue(job.selectedVideos[0].source.isJobInputFile)
}

func testCreateJobRejectsInvalidSnapshotBeforePersistingOrCopying() async throws {
    let store = InMemoryHighlightJobStore()
    let sourceURL = temporaryDirectory.appendingPathComponent("source.mov")
    try Data([1]).write(to: sourceURL)
    let manager = HighlightJobManager(
        store: store,
        fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
        runnerFactory: { _ in .immediateCompleted },
    )
    let invalid = [
        ConfirmedHighlightSegment(
            id: UUID(), videoID: sourceURL.absoluteString, markerIDs: [],
            start: 0, duration: 1,
            markerNumberLowerBound: 1, markerNumberUpperBound: 1, markerTotalCount: 1,
        ),
    ]

    do {
        _ = try await manager.createJob(
            session: self.makeSession(),
            selectedVideos: [
                SelectedTrainingVideo(
                    id: sourceURL.absoluteString,
                    recordedStartAt: Date(timeIntervalSince1970: 2_000),
                    duration: 900,
                ),
            ],
            clipSettings: .default,
            confirmedSegments: invalid,
        )
        XCTFail("Expected invalid snapshot")
    } catch {
        XCTAssertEqual(error as? HighlightClipReviewPlanningError, .missingMarkers)
    }
    XCTAssertTrue(try store.loadJobs().isEmpty)
}
```

- [ ] **Step 2: Add the complete Runner version-discriminator matrix**

Extend the Runner helper so it can set `clipPlanVersion` and `confirmedSegments`. Add these named tests:

```swift
func testVersionOneUsesExactSnapshotWithoutLegacyReplanning() async throws {
    var job = try makeJob(
        status: .queued,
        selectedVideos: [
            HighlightJobVideo(
                id: "video",
                recordedStartAt: Date(timeIntervalSince1970: 5_000),
                duration: 60,
                source: .photoLibraryAsset(localIdentifier: "video"),
            ),
        ],
    )
    let markerID = job.trainingSession.events[0].id
    let snapshot = ConfirmedHighlightSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000030201")!,
        videoID: "video",
        markerIDs: [markerID],
        start: 1.2,
        duration: 3.4,
        markerNumberLowerBound: 1,
        markerNumberUpperBound: 1,
        markerTotalCount: 1,
    )
    job.clipPlanVersion = 1
    job.confirmedSegments = [snapshot]
    var received: [HighlightClipSegment] = []
    let runner = makeSuccessfulRunner { received = $0 }

    let completed = try await runner.run(job: job) { _ in }

    XCTAssertEqual(completed.status, .completed)
    XCTAssertEqual(received, [snapshot.highlightClipSegment])
}

func testLegacyJobWithBothFieldsNilStillUsesEmbeddedSettings() async throws {
    var job = try makeJob(status: .queued)
    job.clipSettings = ClipSettings(secondsBeforeMarker: 7, secondsAfterMarker: 3)
    job.clipPlanVersion = nil
    job.confirmedSegments = nil
    var received: [HighlightClipSegment] = []

    let completed = try await makeSuccessfulRunner { received = $0 }
        .run(job: job) { _ in }

    XCTAssertEqual(completed.status, .completed)
    XCTAssertEqual(received.first?.start, 113)
    XCTAssertEqual(received.first?.duration, 10)
}

private func makeSuccessfulRunner(
    receiveSegments: @escaping ([HighlightClipSegment]) -> Void,
) throws -> HighlightJobRunner {
    let exportedURL = temporaryDirectory.appendingPathComponent("runner-export.mov")
    try Data([1, 2, 3]).write(to: exportedURL)
    return HighlightJobRunner(
        fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
        makeHighlightClip: { segments, _, progress, _ in
            receiveSegments(segments)
            let markerCount = segments.reduce(0) { $0 + $1.coveredMarkerCount }
            progress(
                HighlightClipGenerationProgress(
                    completedMarkerCount: markerCount,
                    totalMarkerCount: markerCount,
                ),
            )
            return exportedURL
        },
        assetForJobVideo: { _, _ in
            AVURLAsset(url: URL(fileURLWithPath: "/tmp/unused.mov"))
        },
    )
}
```

For the legacy expectation, use the helper job’s actual `recordedStartAt` and marker time; if those values remain 2,000 and 2,120, the correct start is 113 and duration is 10.

Add one table-driven test that runs these cases and asserts `.failed`, no export call, and the exact localized message:

| `clipPlanVersion` | `confirmedSegments` | Message |
| --- | --- | --- |
| `nil` | non-`nil` | `任务缺少片段计划版本，请重新创建集锦。` |
| `1` | `nil` | `任务缺少已确认片段，请重新创建集锦。` |
| `1` | `[]` | `任务的已确认片段无效，请重新创建集锦。` |
| `2` | any value | `任务使用了不支持的片段计划版本，请重新创建集锦。` |
| `1` | non-tenth/out-of-bounds snapshot | `任务的已确认片段无效，请重新创建集锦。` |

Also add `testRestartAndLaunchRecoveryKeepVersionOneSnapshot` in manager tests: load an interrupted version 1 job, restart it, capture the job passed to `runnerFactory`, and assert the same version and segment array.

- [ ] **Step 3: Run focused tests and verify the new contract fails**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests \
  -only-testing:ShotMarkerTests/HighlightJobRunnerTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: create signature and version routing failures.

- [ ] **Step 4: Require and validate confirmed segments during new job creation**

Change the manager signature to:

```swift
func createJob(
    session: TrainingSession,
    selectedVideos: [SelectedTrainingVideo],
    clipSettings: ClipSettings,
    confirmedSegments: [ConfirmedHighlightSegment],
) async throws -> HighlightJob
```

Inside `createJob`:

1. Call `HighlightClipReviewPlanner.validateConfirmedSegments` with `Set(session.events.map(\.id))` before allocating/copying task inputs.
2. Build `referencedVideoIDs` from the validated segments and filter `selectedVideos` in their existing selection order.
3. Copy only filtered file URLs; wrap the copy loop and job construction in `do/catch`, call `removeAllFiles(for: jobID)` on partial-copy failure, then rethrow.
4. Create `HighlightJob` with `clipPlanVersion: 1`, the unchanged validated segment array, normalized `ClipSettings`, and filtered `HighlightJobVideo` values.
5. Log only segment/video/marker counts and total duration; remove the current raw `jobID` from any newly added review-specific log context. Do not add Analytics calls.

Update every production and test call site; do not keep an overload that creates a new job without confirmed segments.

- [ ] **Step 5: Implement explicit Runner routing**

Add this error contract beside `HighlightJobRunnerError`:

```swift
enum HighlightJobClipPlanError: LocalizedError, Equatable {
    case snapshotWithoutVersion
    case missingVersionOneSnapshot
    case invalidVersionOneSnapshot
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .snapshotWithoutVersion:
            "任务缺少片段计划版本，请重新创建集锦。"
        case .missingVersionOneSnapshot:
            "任务缺少已确认片段，请重新创建集锦。"
        case .invalidVersionOneSnapshot:
            "任务的已确认片段无效，请重新创建集锦。"
        case .unsupportedVersion:
            "任务使用了不支持的片段计划版本，请重新创建集锦。"
        }
    }
}
```

Move segment resolution inside the Runner’s existing `do/catch` and switch on both fields:

```swift
switch (job.clipPlanVersion, job.confirmedSegments) {
case (nil, nil):
    let legacy = VideoClipSegmentPlanner.highlightPlan(
        for: job.trainingSession,
        videos: job.selectedVideos.map(\.selectedTrainingVideo),
        clipSettings: job.clipSettings,
    )
    guard legacy.canGenerate else { throw HighlightJobRunnerError.noMatchedMarkers }
    segments = legacy.segments
case (nil, .some):
    throw HighlightJobClipPlanError.snapshotWithoutVersion
case (1, nil):
    throw HighlightJobClipPlanError.missingVersionOneSnapshot
case (1, .some(let confirmed)):
    do {
        segments = try HighlightClipReviewPlanner.validateConfirmedSegments(
            confirmed,
            videos: job.selectedVideos.map(\.selectedTrainingVideo),
            validMarkerIDs: Set(job.trainingSession.events.map(\.id)),
        ).map(\.highlightClipSegment)
    } catch {
        throw HighlightJobClipPlanError.invalidVersionOneSnapshot
    }
case (.some(_), _):
    throw HighlightJobClipPlanError.unsupportedVersion
}
```

Add `noMatchedMarkers` to `HighlightJobRunnerError` with the existing message. Completion progress uses `segments.reduce(0) { $0 + $1.coveredMarkerCount }` for both branches. Never call default planning after entering the version 1 case.

- [ ] **Step 6: Keep the export service range-preserving**

Update `HighlightClipSegment` construction in `VideoClipEditingServiceTests`; production export continues to use `segment.start`, `segment.duration`, `markerIDs.count`, number bounds and timescale 600. Add an assertion in the version 1 Runner test that the export closure receives exactly `1.2` and `3.4`, and keep all existing audio/orientation/style tests green.

- [ ] **Step 7: Run focused manager, Runner and export suites**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests \
  -only-testing:ShotMarkerTests/HighlightJobRunnerTests \
  -only-testing:ShotMarkerTests/VideoClipEditingServiceTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all three suites pass; no version 1 test reaches legacy planning.

- [ ] **Step 8: Commit the task pipeline**

```bash
git add \
  ShotMarker/ViewModels/HighlightJobManager.swift \
  ShotMarker/Services/HighlightJobRunner.swift \
  ShotMarker/Services/VideoClipEditingService.swift \
  ShotMarkerTests/HighlightJobManagerTests.swift \
  ShotMarkerTests/HighlightJobRunnerTests.swift \
  ShotMarkerTests/VideoClipEditingServiceTests.swift
git commit -m "feat: 固化确认片段并兼容旧任务"
```

---

### Task 5: 提供可取消、带上限缓存的审核媒体帧

**Files:**

- Create: `ShotMarker/Services/HighlightClipReviewMediaProvider.swift`
- Create: `ShotMarkerTests/HighlightClipReviewMediaProviderTests.swift`

**Interfaces:**

- Produces: `HighlightClipFrameRequest(videoID:time:targetSize:)`
- Produces: `HighlightClipReviewMediaError.invalidRequest`, `.sourceUnavailable`, `.assetLoadFailed`, `.frameUnavailable`
- Produces: `@MainActor HighlightClipReviewMediaProvider.asset(for:)`
- Produces: `frameData(for:at:targetSize:) async throws -> Data`
- Produces: `thumbnailData(for:video:targetSize:) async throws -> Data`
- Produces: `filmstripFrames(for:timeRange:count:targetSize:) async throws -> [Data?]`
- Produces: `removeAllCachedResources()`
- Consumes: current `PhotoLibraryVideoAssetProvider` and file-URL `SelectedTrainingVideo.id`

- [ ] **Step 1: Write failing sampling, cache and cancellation tests**

Create `HighlightClipReviewMediaProviderTests.swift` with an injected `loadAsset` and `generateFrame` closure. Use `AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov"))` as the inert asset. Cover:

```swift
@testable import ShotMarker
import AVFoundation
import XCTest

@MainActor
func testThumbnailUsesCurrentRangeMidpointAndExactTargetSize() async throws {
    var requests: [HighlightClipFrameRequest] = []
    let provider = makeProvider { request in
        requests.append(request)
        return Data([1])
    }
    let item = makeItem(start: 4, duration: 6)

    _ = try await provider.thumbnailData(
        for: item,
        video: makeVideo(),
        targetSize: CGSize(width: 320, height: 180),
    )

    XCTAssertEqual(requests.map(\.time), [7])
    XCTAssertEqual(requests.map(\.targetSize), [CGSize(width: 320, height: 180)])
}

@MainActor
func testFilmstripSamplesUniformBinCentersInsideLocalWindow() async throws {
    var times: [TimeInterval] = []
    let provider = makeProvider { request in
        times.append(request.time)
        return Data([1])
    }

    _ = try await provider.filmstripFrames(
        for: makeVideo(),
        timeRange: HighlightClipRange(start: 0, duration: 12),
        count: 3,
        targetSize: CGSize(width: 120, height: 80),
    )

    XCTAssertEqual(times, [2, 6, 10])
}

@MainActor
func testIdenticalFrameRequestHitsCacheButSizeAndVideoRemainPartOfKey() async throws {
    var generationCount = 0
    let provider = makeProvider(cacheLimit: 8) { _ in
        generationCount += 1
        return Data([UInt8(generationCount)])
    }
    let item = makeItem(start: 4, duration: 6)

    _ = try await provider.thumbnailData(for: item, video: makeVideo(), targetSize: .init(width: 100, height: 100))
    _ = try await provider.thumbnailData(for: item, video: makeVideo(), targetSize: .init(width: 100, height: 100))
    _ = try await provider.thumbnailData(for: item, video: makeVideo(), targetSize: .init(width: 200, height: 100))

    XCTAssertEqual(generationCount, 2)
}

@MainActor
func testCacheEvictsLeastRecentlyUsedEntryAtConfiguredLimit() async throws {
    var generationCount = 0
    let provider = makeProvider(cacheLimit: 2) { _ in
        generationCount += 1
        return Data([UInt8(generationCount)])
    }

    _ = try await provider.frameData(for: makeVideo(), at: 1, targetSize: .init(width: 10, height: 10))
    _ = try await provider.frameData(for: makeVideo(), at: 2, targetSize: .init(width: 10, height: 10))
    _ = try await provider.frameData(for: makeVideo(), at: 3, targetSize: .init(width: 10, height: 10))
    _ = try await provider.frameData(for: makeVideo(), at: 1, targetSize: .init(width: 10, height: 10))

    XCTAssertEqual(generationCount, 4)
}

@MainActor
func testCancellationCancelsInFlightFrameGeneration() async {
    let started = expectation(description: "frame generation started")
    let cancelled = expectation(description: "frame generation cancelled")
    let provider = makeProvider { _ in
        started.fulfill()
        return try await withTaskCancellationHandler {
            try await Task.sleep(for: .seconds(60))
            return Data([1])
        } onCancel: {
            cancelled.fulfill()
        }
    }
    let task = Task {
        try await provider.frameData(
            for: makeVideo(),
            at: 1,
            targetSize: .init(width: 10, height: 10),
        )
    }
    await fulfillment(of: [started], timeout: 1)

    task.cancel()

    do {
        _ = try await task.value
        XCTFail("Expected cancellation")
    } catch is CancellationError {
        // Expected.
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
    await fulfillment(of: [cancelled], timeout: 1)
}

private func makeProvider(
    cacheLimit: Int = 64,
    generate: @escaping (HighlightClipFrameRequest) async throws -> Data,
) -> HighlightClipReviewMediaProvider {
    HighlightClipReviewMediaProvider(
        cacheLimit: cacheLimit,
        loadAsset: { _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov")) },
        generateFrame: { _, request in try await generate(request) },
    )
}

private func makeVideo(id: String = "video") -> SelectedTrainingVideo {
    SelectedTrainingVideo(
        id: id,
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )
}

private func makeItem(start: TimeInterval, duration: TimeInterval) -> HighlightClipReviewItem {
    HighlightClipReviewItem(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000080001")!,
        videoID: "video",
        markerReferences: [
            HighlightClipMarkerReference(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000080101")!,
                markedAt: Date(timeIntervalSince1970: 110),
                timeInVideo: 10,
                originalMatchedNumber: 1,
            ),
        ],
        defaultStart: start,
        defaultDuration: duration,
        start: start,
        duration: duration,
        isIncluded: true,
    )
}
```

- [ ] **Step 2: Run the focused media test and verify it fails**

Use the standard iPhone 17 Pro / iOS 26.5 command with `-only-testing:ShotMarkerTests/HighlightClipReviewMediaProviderTests`. Expected: missing provider types.

- [ ] **Step 3: Implement deterministic cache and frame requests**

Define `HighlightClipFrameRequest: Hashable` with `videoID`, a timescale-600 integer `timeValue`, integer pixel width/height, plus computed `time`/`targetSize` for tests. Implement an LRU array/dictionary capped by an injected `cacheLimit` (default 64); do not rely on nondeterministic `NSCache` eviction in tests.

Use `HighlightClipReviewMediaError.sourceUnavailable` only when a file URL no longer exists or PhotoKit no longer returns the selected asset. Use `.assetLoadFailed` for retryable AVAsset acquisition errors, `.frameUnavailable` for individual image-generation failures, and `.invalidRequest` for non-finite time/size or non-positive frame count. This closed classification is what the ViewModel logs and uses to decide whether an included card must block confirmation.

The provider initializer accepts:

```swift
init(
    cacheLimit: Int = 64,
    loadAsset: @escaping (SelectedTrainingVideo) async throws -> AVAsset,
    generateFrame: @escaping (AVAsset, HighlightClipFrameRequest) async throws -> Data,
)
```

`thumbnailData` uses `start + duration / 2`. `filmstripFrames` accepts the already available `HighlightClipRange` so this task does not depend on the later SwiftUI timeline type; it rejects count <= 0, loads the asset once, samples bin centers, calls `Task.checkCancellation()` between frames and returns `[Data?]` in time order. A per-frame generation error becomes `nil` so the timeline can render a neutral cell; cancellation is rethrown immediately, and failure to load the source asset is rethrown so the ViewModel can classify source availability. `removeAllCachedResources` clears both asset and frame caches.

- [ ] **Step 4: Add the live AVFoundation/PhotoKit implementation**

`HighlightClipReviewMediaProvider.live(...)` resolves a file URL ID with `AVURLAsset`; otherwise it gets the `PHAsset` and calls the existing provider with `.medium` delivery quality after the existing video-preparation gate. The live frame generator must:

- set `AVAssetImageGenerator.appliesPreferredTrackTransform = true`;
- set `maximumSize` from the request;
- generate at the requested timescale-600 time;
- JPEG-encode at quality 0.72;
- use `withTaskCancellationHandler` and `cancelAllCGImageGeneration()`;
- throw a typed media error when no frame is returned, without converting it to card exclusion.

Do not enable a new unconfirmed iCloud download path; this provider is constructed only from `selectedVideoItems.availableVideos` after current readiness completes.

- [ ] **Step 5: Run media tests and commit**

Expected: sampling, cache and cancellation tests pass.

```bash
git add \
  ShotMarker/Services/HighlightClipReviewMediaProvider.swift \
  ShotMarkerTests/HighlightClipReviewMediaProviderTests.swift
git commit -m "feat: 增加审核媒体帧加载"
```

---

### Task 6: 实现审核 ViewModel 与草稿生命周期状态

**Files:**

- Create: `ShotMarker/ViewModels/HighlightClipReviewViewModel.swift`
- Create: `ShotMarkerTests/HighlightClipReviewViewModelTests.swift`

**Interfaces:**

- Produces: `@MainActor final class HighlightClipReviewViewModel: ObservableObject`
- Produces: `items`, `summary`, `thumbnailStates`, `unavailableItemIDs`, `itemErrorMessages`, `planningErrorMessage`, `editingItemID`, `isSubmitting`, `submissionErrorMessage`
- Produces: `setIncluded(_:itemID:)`, `apply(_:itemID:)`, `restoreDefault(itemID:)`, `loadThumbnail(itemID:targetSize:)`, `markSourceUnavailable(itemID:)`
- Produces: `openEditor(itemID:)`, `closeEditor()`, `confirmedSegments() throws -> [ConfirmedHighlightSegment]`, `submit()`
- Produces: `hasUserChanges`, `canConfirm`, `requiresInvalidation(videos:clipSettings:)`
- Consumes: `HighlightClipReviewPlanner`, `HighlightClipReviewMediaProvider` and an injected async submit closure

- [ ] **Step 1: Write failing state-transition tests**

Create the test file with fixed draft/video helpers and cover these exact transitions:

```swift
@testable import ShotMarker
import AVFoundation
import XCTest

@MainActor
func testExcludeRestoreAndRangeEditsKeepStableCardIdentity() throws {
    let viewModel = makeViewModel()
    let id = viewModel.items[0].id

    try viewModel.apply(.moveBy(0.5), itemID: id)
    viewModel.setIncluded(false, itemID: id)
    viewModel.setIncluded(true, itemID: id)

    XCTAssertEqual(viewModel.items[0].id, id)
    XCTAssertEqual(viewModel.items[0].start, 0.5)
    XCTAssertTrue(viewModel.items[0].isIncluded)
    XCTAssertTrue(viewModel.hasUserChanges)
}

@MainActor
func testRestoreDefaultOnlyChangesCurrentCardRangeAndNotInclusion() throws {
    let viewModel = makeViewModel(itemCount: 2)
    let firstID = viewModel.items[0].id
    let secondBefore = viewModel.items[1]
    try viewModel.apply(.moveBy(1), itemID: firstID)
    viewModel.setIncluded(false, itemID: firstID)

    viewModel.restoreDefault(itemID: firstID)

    XCTAssertEqual(viewModel.items[0].range, viewModel.items[0].defaultRange)
    XCTAssertFalse(viewModel.items[0].isIncluded)
    XCTAssertEqual(viewModel.items[1], secondBefore)
}

@MainActor
func testNoIncludedOrIncludedUnavailableCardDisablesConfirmation() {
    let viewModel = makeViewModel()
    let id = viewModel.items[0].id

    viewModel.setIncluded(false, itemID: id)
    XCTAssertFalse(viewModel.canConfirm)

    viewModel.setIncluded(true, itemID: id)
    viewModel.markSourceUnavailable(itemID: id)
    XCTAssertFalse(viewModel.canConfirm)

    viewModel.setIncluded(false, itemID: id)
    XCTAssertFalse(viewModel.canConfirm) // still empty, not blocked by unavailable state itself
}

@MainActor
func testThumbnailFailureShowsPlaceholderWithoutMarkingSourceUnavailable() async {
    let viewModel = makeViewModel(frameResults: [.failure(TestError.frameFailed)])
    let id = viewModel.items[0].id

    await viewModel.loadThumbnail(itemID: id, targetSize: .init(width: 200, height: 120))

    XCTAssertEqual(viewModel.thumbnailStates[id], .placeholder)
    XCTAssertFalse(viewModel.unavailableItemIDs.contains(id))
    XCTAssertTrue(viewModel.canConfirm)
}

@MainActor
func testEditedRangeRefreshesMidpointThumbnailWithoutClearingPreviousImage() async throws {
    let viewModel = makeViewModel(frameResults: [.success(Data([1])), .success(Data([2]))])
    let id = viewModel.items[0].id
    await viewModel.loadThumbnail(itemID: id, targetSize: .init(width: 200, height: 120))

    try viewModel.apply(.moveBy(1), itemID: id)
    let refresh = Task {
        await viewModel.loadThumbnail(itemID: id, targetSize: .init(width: 200, height: 120))
    }

    XCTAssertEqual(viewModel.thumbnailStates[id], .loaded(Data([1])))
    await refresh.value
    XCTAssertEqual(viewModel.thumbnailStates[id], .loaded(Data([2])))
}

@MainActor
func testSubmitUsesCurrentSummarySegmentsAndPreservesDraftOnFailure() async throws {
    var submitted: [ConfirmedHighlightSegment] = []
    let viewModel = makeViewModel { segments in
        submitted = segments
        throw TestError.submitFailed
    }
    let originalItems = viewModel.items

    await viewModel.submit()

    XCTAssertEqual(submitted, viewModel.summary.finalSegments)
    XCTAssertEqual(viewModel.items, originalItems)
    XCTAssertEqual(viewModel.submissionErrorMessage, "submitFailed")
    XCTAssertFalse(viewModel.isSubmitting)
}

private func makeViewModel(
    itemCount: Int = 1,
    frameResults: [Result<Data, TestError>] = [.success(Data([1]))],
    submitSegments: @escaping ([ConfirmedHighlightSegment]) async throws -> Void = { _ in },
) -> HighlightClipReviewViewModel {
    var nextFrameIndex = 0
    let video = SelectedTrainingVideo(
        id: "video",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )
    let mediaProvider = HighlightClipReviewMediaProvider(
        cacheLimit: 8,
        loadAsset: { _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov")) },
        generateFrame: { _, _ in
            defer { nextFrameIndex += 1 }
            return try frameResults[min(nextFrameIndex, frameResults.count - 1)].get()
        },
    )
    let items = (0 ..< itemCount).map { index in
        let number = index + 1
        let markerID = UUID(
            uuidString: String(format: "00000000-0000-0000-0000-%012d", 70_100 + number),
        )!
        return HighlightClipReviewItem(
            id: UUID(
                uuidString: String(format: "00000000-0000-0000-0000-%012d", 70_000 + number),
            )!,
            videoID: video.id,
            markerReferences: [
                HighlightClipMarkerReference(
                    id: markerID,
                    markedAt: Date(timeIntervalSince1970: 110 + Double(index * 5)),
                    timeInVideo: 10 + Double(index * 5),
                    originalMatchedNumber: number,
                ),
            ],
            defaultStart: Double(index * 5),
            defaultDuration: 2,
            start: Double(index * 5),
            duration: 2,
            isIncluded: true,
        )
    }
    return HighlightClipReviewViewModel(
        draft: HighlightClipReviewDraft(
            selectedVideoCount: 1,
            totalMarkerCount: itemCount,
            items: items,
        ),
        videos: [video],
        clipSettings: .default,
        mediaProvider: mediaProvider,
        submitSegments: submitSegments,
    )
}

private enum TestError: LocalizedError {
    case frameFailed
    case submitFailed

    var errorDescription: String? { String(describing: self) }
}
```

Also add:

- `testSummaryRefreshesAfterEveryIncludeAndRangeChange` and assert all four summary values;
- `testOpeningAnotherEditorKeepsDraftAndChangesOnlyEditingID`;
- `testVideoIdentityDurationOrBeforeAfterChangeRequiresInvalidation`;
- `testMarkerLabelStyleOnlyChangeDoesNotRequireInvalidation`;
- `testConfirmedSegmentsReturnsTheAlreadyDisplayedSummaryArray`;
- `testDuplicateSubmitWhileSubmittingCallsClosureOnce`.

- [ ] **Step 2: Run the focused ViewModel suite and verify it fails**

Run the standard simulator command with `-only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests`. Expected: missing ViewModel and thumbnail state.

- [ ] **Step 3: Implement state ownership and summary refresh**

Define:

```swift
enum HighlightClipThumbnailState: Equatable {
    case idle
    case loading
    case loaded(Data)
    case placeholder
}
```

The non-throwing ViewModel initializer receives a `HighlightClipReviewDraft`, `[SelectedTrainingVideo]`, `ClipSettings`, media provider and `submitSegments: ([ConfirmedHighlightSegment]) async throws -> Void`. Keep an immutable `originalItems` copy and a `HighlightClipReviewInputFingerprint` containing ordered video identity/start/duration plus before/after seconds; explicitly exclude `markerLabelStyle`. Initialize a zero-final-segment summary from the draft’s marker counts, then call `refreshSummary`; if the draft is unexpectedly invalid, retain the safe summary, set `planningErrorMessage`, and disable confirmation instead of crashing.

Every mutation finds the card by stable UUID, applies the planner rule, and immediately replaces `summary` with `makeSummary`. A rejected range edit records the localized error under that item ID and rethrows for haptic/alert feedback; a successful edit clears that item’s error. A summary failure sets `planningErrorMessage` and keeps the last valid summary. `confirmedSegments()` returns `summary.finalSegments` after a final call to `validateConfirmedSegments` using `Set(items.flatMap(\.markerReferences).map(\.id))`; it must not run a second merge algorithm.

`canConfirm` is true only when the displayed final array is nonempty, every included card is available and has no `itemErrorMessages` entry, `planningErrorMessage` is empty, and there is no submission in progress. Errors on an excluded card remain visible for later recovery but do not block other valid included cards. A thumbnail failure sets `.placeholder`; only an explicit AVAsset/source-not-found classification adds the item to `unavailableItemIDs`.

- [ ] **Step 4: Implement task cancellation and submission behavior**

Store one thumbnail `Task` per item ID. A new request for the same item cancels its predecessor; changing a range schedules a new midpoint request. If an old image exists, keep `.loaded(oldData)` visible during refresh and replace it only on success; first-load requests use `.loading`, and a failed refresh keeps the old image rather than clearing the edit. Closing the flow cancels all tasks and clears media caches. `openEditor` changes only `editingItemID`; the editor owns filmstrip/player requests and cancels them when its ID changes.

`submit()` guards `canConfirm && !isSubmitting`, obtains the currently displayed array through `try confirmedSegments()` (validation only; no recomputation), sets `isSubmitting`, awaits the injected closure, and on error restores only submission state/error—not draft items. It does not dismiss views or write training records.

- [ ] **Step 5: Run ViewModel and planner suites, then commit**

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: both suites pass.

```bash
git add \
  ShotMarker/ViewModels/HighlightClipReviewViewModel.swift \
  ShotMarkerTests/HighlightClipReviewViewModelTests.swift
git commit -m "feat: 增加片段审核状态管理"
```

---

### Task 7: 实现单片段范围播放控制器

**Files:**

- Create: `ShotMarker/ViewModels/HighlightClipPlaybackController.swift`
- Create: `ShotMarkerTests/HighlightClipPlaybackControllerTests.swift`

**Interfaces:**

- Produces: `@MainActor protocol HighlightClipPlaybackEngine`
- Produces: `AVPlayerHighlightClipPlaybackEngine`
- Produces: `@MainActor final class HighlightClipPlaybackController: ObservableObject`
- Produces: `load(video:range:)`, `play()`, `pause()`, `preview(at:)`, `previewStart(of:)`, `previewEnd(of:)`, `updateRange(_:)`, `reset()`
- Publishes: `player`, `currentTime`, `isPlaying`, `isLoading`, `loadError: HighlightClipReviewMediaError?`, `errorMessage`
- Consumes: one asset loader from `HighlightClipReviewMediaProvider`

- [ ] **Step 1: Write failing controller tests against a spy engine**

The spy engine records replace/play/pause/seek/observer calls and exposes methods to fire periodic and boundary callbacks. Add:

```swift
@testable import ShotMarker
import AVFoundation
import XCTest

@MainActor
func testLoadPausesAtRangeStartWithoutAutoplay() async {
    let engine = SpyHighlightClipPlaybackEngine()
    let controller = makeController(engine: engine)

    await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))

    XCTAssertEqual(engine.replacedAssetCount, 1)
    XCTAssertEqual(engine.seekedTimes, [4])
    XCTAssertEqual(engine.playCallCount, 0)
    XCTAssertFalse(controller.isPlaying)
}

@MainActor
func testPlayStopsAtEndAndReturnsToStart() async {
    let engine = SpyHighlightClipPlaybackEngine()
    let controller = makeController(engine: engine)
    await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))

    controller.play()
    engine.fireBoundaryObserver()
    await Task.yield()

    XCTAssertEqual(engine.playCallCount, 1)
    XCTAssertEqual(engine.pauseCallCount, 2) // initial load plus boundary
    XCTAssertEqual(engine.seekedTimes.last, 4)
    XCTAssertFalse(controller.isPlaying)
}

@MainActor
func testRangeAndCursorPreviewPauseAtSpecifiedFrames() async {
    let engine = SpyHighlightClipPlaybackEngine()
    let controller = makeController(engine: engine)
    await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))

    await controller.previewStart(of: .init(start: 5, duration: 2))
    await controller.previewEnd(of: .init(start: 5, duration: 2))
    await controller.preview(at: 5.5)

    XCTAssertEqual(engine.seekedTimes[1], 5)
    XCTAssertEqual(engine.seekedTimes[2], 7 - 1.0 / 600.0, accuracy: 0.000_001)
    XCTAssertEqual(engine.seekedTimes[3], 5.5)
}

@MainActor
func testSwitchAndResetRemoveObserversAndReleasePlayerItem() async {
    let engine = SpyHighlightClipPlaybackEngine()
    let controller = makeController(engine: engine)
    await controller.load(video: makeVideo(id: "first"), range: .init(start: 0, duration: 2))
    await controller.load(video: makeVideo(id: "second"), range: .init(start: 1, duration: 2))
    controller.reset()

    XCTAssertEqual(engine.removedObserverCount, 4)
    XCTAssertEqual(engine.clearCallCount, 2)
}

@MainActor
private func makeController(
    engine: SpyHighlightClipPlaybackEngine,
    loadAsset: @escaping (SelectedTrainingVideo) async throws -> AVAsset = { _ in
        AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov"))
    },
) -> HighlightClipPlaybackController {
    HighlightClipPlaybackController(engine: engine, loadAsset: loadAsset)
}

private func makeVideo(id: String = "video") -> SelectedTrainingVideo {
    SelectedTrainingVideo(
        id: id,
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )
}

@MainActor
private final class SpyHighlightClipPlaybackEngine: HighlightClipPlaybackEngine {
    let player = AVPlayer()
    private(set) var replacedAssetCount = 0
    private(set) var clearCallCount = 0
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var seekedTimes: [TimeInterval] = []
    private(set) var removedObserverCount = 0
    private var periodicHandler: ((TimeInterval) -> Void)?
    private var boundaryHandler: (() -> Void)?

    func replaceCurrentItem(with _: AVAsset) { replacedAssetCount += 1 }
    func clearCurrentItem() { clearCallCount += 1 }
    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func seek(to seconds: TimeInterval) async { seekedTimes.append(seconds) }

    func addPeriodicTimeObserver(
        _ handler: @escaping (TimeInterval) -> Void,
    ) -> Any {
        periodicHandler = handler
        return UUID()
    }

    func addBoundaryTimeObserver(
        at _: TimeInterval,
        _ handler: @escaping () -> Void,
    ) -> Any {
        boundaryHandler = handler
        return UUID()
    }

    func removeTimeObserver(_: Any) { removedObserverCount += 1 }
    func firePeriodicObserver(at time: TimeInterval) { periodicHandler?(time) }
    func fireBoundaryObserver() { boundaryHandler?() }
}
```

Also test that periodic callbacks update `currentTime`, play seeks to start when the cursor is outside the selection, `.assetLoadFailed` exposes a retryable typed error, and `.sourceUnavailable` remains distinguishable so the editor can block an included card. Neither failure may modify the review range.

- [ ] **Step 2: Run the controller suite and verify it fails**

Run the standard simulator command with `-only-testing:ShotMarkerTests/HighlightClipPlaybackControllerTests`. Expected: missing controller and engine protocol.

- [ ] **Step 3: Implement a testable player engine boundary**

Define this exact protocol; the live adapter wraps exactly one `AVPlayer` and never creates simultaneous player items:

```swift
@MainActor
protocol HighlightClipPlaybackEngine: AnyObject {
    var player: AVPlayer { get }
    func replaceCurrentItem(with asset: AVAsset)
    func clearCurrentItem()
    func play()
    func pause()
    func seek(to seconds: TimeInterval) async
    func addPeriodicTimeObserver(_ handler: @escaping (TimeInterval) -> Void) -> Any
    func addBoundaryTimeObserver(at seconds: TimeInterval, _ handler: @escaping () -> Void) -> Any
    func removeTimeObserver(_ token: Any)
}
```

The controller must:

- pause and seek to the selected start after loading, without autoplay;
- replace the boundary observer whenever the range end changes;
- on boundary callback pause, seek to start and publish `isPlaying = false`;
- seek to `end - 1/600` for end-handle preview;
- keep cursor preview independent of the range;
- remove both observer tokens before switching assets, on `reset`, and during deinitialization;
- call `replaceCurrentItem(with: nil)` on reset so the old asset is released.

- [ ] **Step 4: Run the controller suite and commit**

Expected: all controller tests pass.

```bash
git add \
  ShotMarker/ViewModels/HighlightClipPlaybackController.swift \
  ShotMarkerTests/HighlightClipPlaybackControllerTests.swift
git commit -m "feat: 增加片段范围播放控制"
```

---

### Task 8: 建立局部时间轴窗口、坐标和手势映射

**Files:**

- Create: `ShotMarker/Models/HighlightClipTimeline.swift`
- Create: `ShotMarker/Views/HighlightClipTimelineView.swift`
- Create: `ShotMarkerTests/HighlightClipTimelineTests.swift`

**Interfaces:**

- Produces: `HighlightClipTimelineWindow(start:duration:)`, `end`
- Produces: `HighlightClipTimelineRole.startHandle`, `.endHandle`, `.moveRange`, `.playhead`
- Produces: `HighlightClipTimelineAction.setStart`, `.setEnd`, `.moveBy`, `.preview`
- Produces: `HighlightClipTimelineGeometry.makeWindow(range:videoDuration:)`
- Produces: `shiftedWindow(_:toContain:videoDuration:)`, `x(for:window:width:)`, `time(forX:window:width:)`, `action(for:translationX:range:playhead:window:width:)`
- Produces: `HighlightClipTimelineView` that emits one unambiguous role-specific action per gesture

- [ ] **Step 1: Write failing local-window and mapping tests**

Create `HighlightClipTimelineTests.swift`:

```swift
@testable import ShotMarker
import XCTest

final class HighlightClipTimelineTests: XCTestCase {
    func testWindowUsesTwentySecondsForShortClipAndCentersFiveOrMoreSecondsOfContext() {
        let window = HighlightClipTimelineGeometry.makeWindow(
            range: HighlightClipRange(start: 20, duration: 4),
            videoDuration: 60,
        )

        XCTAssertEqual(window, HighlightClipTimelineWindow(start: 12, duration: 20))
    }

    func testWindowUsesClipLengthPlusTenSecondsForLongClip() {
        let window = HighlightClipTimelineGeometry.makeWindow(
            range: HighlightClipRange(start: 20, duration: 14),
            videoDuration: 60,
        )

        XCTAssertEqual(window, HighlightClipTimelineWindow(start: 15, duration: 24))
    }

    func testWindowTransfersUnavailableContextAtVideoEdges() {
        XCTAssertEqual(
            HighlightClipTimelineGeometry.makeWindow(
                range: .init(start: 1, duration: 4), videoDuration: 60,
            ),
            HighlightClipTimelineWindow(start: 0, duration: 20),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.makeWindow(
                range: .init(start: 55, duration: 4), videoDuration: 60,
            ),
            HighlightClipTimelineWindow(start: 40, duration: 20),
        )
    }

    func testVideoShorterThanTargetWindowShowsCompleteVideo() {
        XCTAssertEqual(
            HighlightClipTimelineGeometry.makeWindow(
                range: .init(start: 2, duration: 4), videoDuration: 8,
            ),
            HighlightClipTimelineWindow(start: 0, duration: 8),
        )
    }

    func testTimeAndXMappingClampToWindowBounds() {
        let window = HighlightClipTimelineWindow(start: 10, duration: 20)

        XCTAssertEqual(HighlightClipTimelineGeometry.x(for: 20, window: window, width: 200), 100)
        XCTAssertEqual(HighlightClipTimelineGeometry.time(forX: 50, window: window, width: 200), 15)
        XCTAssertEqual(HighlightClipTimelineGeometry.time(forX: -20, window: window, width: 200), 10)
        XCTAssertEqual(HighlightClipTimelineGeometry.time(forX: 240, window: window, width: 200), 30)
    }

    func testEachDragRoleProducesOnlyItsOwnAction() {
        let window = HighlightClipTimelineWindow(start: 0, duration: 20)
        let range = HighlightClipRange(start: 5, duration: 4)

        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .startHandle, translationX: 20, range: range, playhead: 5,
                window: window, width: 200,
            ),
            .setStart(7),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .endHandle, translationX: 20, range: range, playhead: 5,
                window: window, width: 200,
            ),
            .setEnd(11),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .moveRange, translationX: 20, range: range, playhead: 5,
                window: window, width: 200,
            ),
            .moveBy(2),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .playhead, translationX: 20, range: range, playhead: 5,
                window: window, width: 200,
            ),
            .preview(7),
        )
    }
}
```

Add `testShiftedWindowFollowsRangeNearEitherEdgeAndStaysInsideVideo`. Use a 20-second window, a two-second desired context margin, move the range to 18–22 and then 1–5, and assert the shifted window contains the range plus available margin without crossing 0 or the video end.

- [ ] **Step 2: Run the timeline tests and verify they fail**

Run the standard simulator command with `-only-testing:ShotMarkerTests/HighlightClipTimelineTests`. Expected: missing timeline types.

- [ ] **Step 3: Implement pure window and gesture geometry**

In `HighlightClipTimeline.swift`:

- target window duration is `min(videoDuration, max(range.duration + 10, 20))`;
- center the target window on the range, then clamp its start to `0 ... videoDuration - targetDuration`, which transfers unavailable context to the other edge;
- `shiftedWindow` keeps at least `min(2, max((window.duration - range.duration) / 2, 0))` seconds of visible context on the approached side when possible;
- x/time mapping clamps both the input coordinate and output time;
- a drag translation converts through `window.duration / width` and emits exactly one action based on the explicit role; start/end/move use the gesture’s initial range, while playhead uses the gesture’s explicit initial `playhead` value;
- invalid/non-finite width or duration returns the unchanged range start/end action rather than emitting NaN.

- [ ] **Step 4: Build the role-separated SwiftUI timeline**

Create `HighlightClipTimelineView.swift` with inputs for `window`, `range`, `playhead`, marker references, frame `[Data?]`, and `onAction`. The view must:

- render frame cells with `.scaledToFit()` on black and neutral placeholders for missing cells;
- draw marker reference lines at their immutable `timeInVideo`, labeled with their current review number supplied by the caller;
- render separate left/right 44-point hit regions, a visibly distinct center move grip, and a thin independently draggable playhead;
- attach one `DragGesture` to each role rather than using location heuristics in one shared gesture;
- keep a gesture’s initial range/time stable through `@GestureState`, then emit planner edits normalized by the ViewModel;
- expose `accessibilityLabel` values “片段起点”, “片段终点”, “移动整个片段”, and “预览位置”, with natural-language time values;
- provide `.accessibilityAdjustableAction` for start/end/move/playhead so VoiceOver does not depend on drag gestures.

- [ ] **Step 5: Run the timeline suite and a compile build, then commit**

Run the focused timeline test followed by:

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: tests and Debug build pass.

```bash
git add \
  ShotMarker/Models/HighlightClipTimeline.swift \
  ShotMarker/Views/HighlightClipTimelineView.swift \
  ShotMarkerTests/HighlightClipTimelineTests.swift
git commit -m "feat: 增加片段审核局部时间轴"
```

---

### Task 9: 构建单片段编辑器和审核图集

**Files:**

- Create: `ShotMarker/Views/HighlightClipEditorView.swift`
- Create: `ShotMarker/Views/HighlightClipReviewView.swift`
- Modify: `ShotMarker/ViewModels/HighlightClipReviewViewModel.swift`
- Modify: `ShotMarkerTests/HighlightClipReviewViewModelTests.swift`

**Interfaces:**

- Produces: `HighlightClipEditorView(viewModel:itemID:playbackController:)`
- Produces: `HighlightClipReviewView(viewModel:makePlaybackController:)`
- Consumes: stable item IDs, displayed summary, shared media provider and already-finalized submit segments
- Preserves: Views contain no merge, numbering, task persistence, PhotoKit lookup or export algorithm

- [ ] **Step 1: Add ViewModel tests for editor action routing and resource ownership**

Before writing Views, extend `HighlightClipReviewViewModelTests`:

- `testStartEndAndMoveFineTuneUseExactlyHalfSecond`: from range 5–9, invoke each public fine-tune method and assert start/end/range move by exactly 0.5 through the canonical planner.
- `testPlayheadPreviewDoesNotMutateRange`: capture item, call preview, assert item unchanged and playback spy receives only the preview time.
- `testFilmstripRefreshCancelsPreviousWindowRequest`: start a suspended request, change the window, assert the first task is cancelled and only the second result is published.
- `testUnavailableIncludedCardCanBeExcludedAndThenOtherCardsSubmit`: with two cards, mark first unavailable, exclude it, and assert the second segment remains confirmable.

Run the ViewModel suite. Expected: the new fine-tune/filmstrip APIs do not yet exist.

- [ ] **Step 2: Add explicit editor intents to the ViewModel**

Expose these methods so the UI never edits `items` directly:

```swift
func adjustStart(itemID: UUID, by delta: TimeInterval) throws
func adjustEnd(itemID: UUID, by delta: TimeInterval) throws
func moveRange(itemID: UUID, by delta: TimeInterval) throws
func handleTimelineAction(
    _ action: HighlightClipTimelineAction,
    itemID: UUID,
    playbackController: HighlightClipPlaybackController,
) async throws
func loadFilmstrip(itemID: UUID, window: HighlightClipTimelineWindow, count: Int, targetSize: CGSize) async
```

The six buttons call with `-0.5`/`+0.5`; labels interpret negative time as “更早” and positive as “更晚”. `HighlightClipEditorView` passes its controller into `handleTimelineAction`; start/end/move actions update the planner then pause and preview the new start/end/start respectively. `.preview` only seeks the playhead and does not mutate the item.

- [ ] **Step 3: Implement the single-clip editor**

Create `HighlightClipEditorView.swift` using `AVKit.VideoPlayer` backed by the controller’s single `AVPlayer`. The page must contain, in order:

1. aspect-fit black playback area with loading/error/retry overlay;
2. current time, start, end and duration using monospaced digits plus natural-language accessibility values;
3. `HighlightClipTimelineView` with local-window filmstrip and fixed marker lines;
4. play/pause and an independent playhead;
5. three labeled fine-tune groups:
   - 起点: `-0.5s 更早`, `+0.5s 更晚`;
   - 终点: `-0.5s 更早`, `+0.5s 更晚`;
   - 整体: `-0.5s 向前`, `+0.5s 向后`;
6. included toggle and “恢复默认范围”.

Set the navigation title from the ViewModel’s current display number, for example `片段 2–3`. Load the asset at the current range without autoplay. On start edits preview the new start; on end edits preview one timescale tick before end; on whole-range edits pause and seek to new start. On disappear cancel the filmstrip task and call `playbackController.reset()`.

Initialize timeline state with `HighlightClipTimelineGeometry.makeWindow`. After a range edit, call `shiftedWindow`; only when the window value changes, cancel the old filmstrip request and load frames for the new window’s `HighlightClipRange`. Do not reset the playhead or card edit merely because frame loading is pending or fails.

When `playbackController.loadError == .sourceUnavailable`, call `viewModel.markSourceUnavailable(itemID:)` and show “排除此片段” plus “返回重新选择视频”. For `.assetLoadFailed`, show Retry without marking the card permanently unavailable. A no-audio asset is not an error and uses the same playback controls.

Every drag has a button/adjustable-action equivalent. Disable only the direction that has reached a boundary/minimum; announce why adjustment cannot continue. “恢复默认范围” must not alter inclusion or any other card.

- [ ] **Step 4: Implement the responsive review gallery**

Create `HighlightClipReviewView.swift` with a `ScrollView`, pinned summary header and `LazyVGrid`. Its injected `makePlaybackController` closure creates the controller only when an editor destination opens; the editor resets it on exit, so there is never more than one active item. Use one flexible column for `dynamicTypeSize.isAccessibilitySize`; otherwise use adaptive columns with a 160-point minimum so narrow widths naturally become one column.

Attach thumbnail loading to each lazily materialized card with `.task(id: item.range)`; scrolling off-screen cancels that task, while the ViewModel/cache preserve successful data. Each card must show:

- a separate always-visible number button with a minimum 44×44 frame;
- a whole-card edit button outside that number button, avoiding nested SwiftUI buttons;
- current midpoint thumbnail `.scaledToFit()` on black, or a neutral placeholder;
- current duration, included/excluded/unavailable state and edit affordance;
- gray treatment plus “已排除” without removing or moving the card;
- “生成时将合并” when its stable ID is in `summary.mergingItemIDs`.

When an edited card returns from the editor, request its new midpoint thumbnail asynchronously. Keep the previous image visible until the replacement arrives; a refresh failure keeps that previous image, while a card with no successful image uses the neutral placeholder. Thumbnail state changes must never overwrite `start`, `duration` or `isIncluded`.

For included cards use `summary.displayNumberRangesByItemID`; excluded cards show their original range. Card accessibility combines number, natural-language duration, state and “打开片段编辑”; unavailable cards announce the reason.

The summary header shows exactly: 保留打点、排除打点、最终片段、预计总时长. The bottom button is “确认并生成”, uses `viewModel.submit()`, and is disabled with an explanatory message when no valid included segment exists or an included source is unavailable. Submission errors stay on the review page and preserve all cards.

- [ ] **Step 5: Add previews that exercise layout states**

Add DEBUG previews for:

- two-column included/excluded/merge-warning cards;
- one unavailable card with placeholder;
- maximum Dynamic Type single-column layout;
- editor containing a merged `2–3` card and three fixed marker lines.

Preview fixtures use inert injected media/player dependencies; they must not request the photo library or create tasks.

- [ ] **Step 6: Run ViewModel tests and Debug build**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests \
  -only-testing:ShotMarkerTests/HighlightClipTimelineTests \
  -only-testing:ShotMarkerTests/HighlightClipPlaybackControllerTests \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: focused suites and app build pass.

- [ ] **Step 7: Commit editor and gallery**

```bash
git add \
  ShotMarker/ViewModels/HighlightClipReviewViewModel.swift \
  ShotMarker/Views/HighlightClipEditorView.swift \
  ShotMarker/Views/HighlightClipReviewView.swift \
  ShotMarkerTests/HighlightClipReviewViewModelTests.swift
git commit -m "feat: 增加片段审核图集与编辑器"
```

---

### Task 10: 把审核阶段接入现有集锦生成流程

**Files:**

- Modify: `ShotMarker/Views/TrainingSessionHighlightView.swift:8-118,155-232,657-788`
- Modify: `ShotMarker/ViewModels/HighlightClipReviewViewModel.swift`
- Modify: `ShotMarkerTests/HighlightClipReviewViewModelTests.swift`
- Modify: `ShotMarkerTests/HighlightJobManagerTests.swift`

**Interfaces:**

- Consumes: prepared `selectedVideoItems.availableVideos`, current before/after settings and marker-label style
- Produces: retained in-memory review ViewModel across gallery/editor/settings navigation
- Produces: guarded input invalidation for video/before/after changes
- Produces: version 1 `createJob(...confirmedSegments:)` call only after page-level confirmation
- Preserves: marker-label style edits without invalidating range draft

- [ ] **Step 1: Add lifecycle and task-creation regression tests**

Extend ViewModel/manager tests with:

- `testReturningFromEditorAndSettingsKeepsSameDraftValues`: edit/exclude, close editor, reopen and assert exact items.
- `testFingerprintTreatsVideoOrderAsPlanningInput`: swap overlapping video order and assert invalidation is required.
- `testSubmittingAfterMarkerStyleChangeUsesSameSegmentsAndLatestStyle`: summary array stays equal; manager job stores the new style.
- `testCreateJobFailureLeavesTemporaryInputsAndReviewDraftAvailableForRetry`: inject a manager/file-store failure, assert ViewModel items remain; temporary selection cleanup callback has not run.
- `testSuccessfulCreationCleansAllPickerTemporaryFilesAfterReferencedFilesAreCopied`: use one retained and one excluded temporary source; assert job has only retained copy, then the flow cleanup receives both selection URLs.

Use injected closures to test cleanup ownership; do not attempt to instantiate `PhotosPickerItem` in unit tests.

- [ ] **Step 2: Replace direct generation with review navigation**

In `TrainingSessionHighlightView`:

- rename the primary action to “下一步：审核片段”;
- keep current coverage errors and video-preparation disable rules;
- on tap call `HighlightClipReviewPlanner.makeDraft`; if empty, keep the existing no-covered-marker error;
- construct one live media provider and one `HighlightClipReviewViewModel`, store it in `@State`, and present `HighlightClipReviewView` through `navigationDestination(isPresented:)`; pass a playback-controller factory backed by that same provider’s `asset(for:)` method;
- returning from editor/gallery to settings retains the same ViewModel as long as its input fingerprint remains valid;
- marker-label style remains bound to `clipSettings` and can change without rebuilding the draft.

The review submit closure reads the latest normalized value through a `Binding<ClipSettings>` backed by the parent `@State` (do not capture a one-time settings value when constructing the ViewModel), then calls:

```swift
try await highlightJobManager.createJob(
    session: session,
    selectedVideos: selectedVideos,
    clipSettings: clipSettings,
    confirmedSegments: confirmedSegments,
)
```

Only after success: cancel preparation/media tasks, clean every picker temporary source, clear selection/draft state, log aggregate counts, and dismiss to the home page. On failure, leave the review page and all temp sources intact for retry.

- [ ] **Step 3: Intercept draft-invalidating setting changes before mutation**

Replace direct before/after Stepper bindings and PhotosPicker selection binding with guarded bindings. If a draft exists and the proposed video selection/order or before/after value changes:

1. keep the current UI value and draft;
2. store one pending mutation;
3. show “重新规划片段？” explaining current排除/调整会丢失;
4. Cancel discards only the pending mutation;
5. Confirm cancels media/player tasks, clears the draft, applies the pending mutation, then reloads/replans when the user next enters review.

Changing only `markerLabelStyle` bypasses this confirmation. Do not compare thumbnails, player state or display numbering in the input fingerprint.

- [ ] **Step 4: Guard exiting the entire flow without breaking review-to-settings navigation**

If `reviewViewModel.hasUserChanges` is true, hide the default flow-level back button and provide a leading button that asks “放弃片段调整？”. Confirm performs full media/preparation/temp cleanup and dismisses; Cancel remains in the flow. Returning from the single editor to the gallery and from the gallery to settings never shows this discard alert.

Revise the current unconditional `.onDisappear` cleanup: navigation from settings to review must not delete picker temporary files. Cleanup belongs only to confirmed task creation or confirmed whole-flow exit. App termination may lose the in-memory draft, as specified; do not add scene storage or disk persistence.

- [ ] **Step 5: Keep logs private and aggregate-only**

Replace new-review contexts with:

- default card count;
- included/excluded marker counts;
- final segment count and total duration;
- whether final merge occurred;
- thumbnail/playback/validation/task-creation error category.

Because this View already participates in the new flow, also remove sensitive values from its existing `highlightContext` and video-preparation logs: drop `trainingSessionId`, replace `videoID` with non-identifying item index/source category, and replace interpolated raw errors with a closed error-category string. Do not log `session.id`, marker/card UUIDs, video IDs, file URLs/names, Photos identifiers, exact reference times or free-form system error descriptions. Do not call `analytics.track` anywhere in review/editor code; existing generate-success remains in `HighlightJobManager` only after final completion.

- [ ] **Step 6: Run all affected focused suites and Debug build**

Run:

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewMediaProviderTests \
  -only-testing:ShotMarkerTests/HighlightClipPlaybackControllerTests \
  -only-testing:ShotMarkerTests/HighlightClipTimelineTests \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests \
  -only-testing:ShotMarkerTests/HighlightJobRunnerTests \
  -only-testing:ShotMarkerTests/VideoClipEditingServiceTests \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all focused tests and app build pass.

- [ ] **Step 7: Commit flow integration**

```bash
git add \
  ShotMarker/Views/TrainingSessionHighlightView.swift \
  ShotMarker/ViewModels/HighlightClipReviewViewModel.swift \
  ShotMarkerTests/HighlightClipReviewViewModelTests.swift \
  ShotMarkerTests/HighlightJobManagerTests.swift
git commit -m "feat: 接入集锦片段审核流程"
```

---

### Task 11: 完成自动验证、资源检查和 Simulator 人工验收

**Files:**

- Modify only if a verification failure requires a tested fix
- Record evidence for: `docs/current/quality.md` in Task 12

**Interfaces:**

- Consumes: Tasks 1–10 implementation
- Produces: fresh focused/full test counts, Release build result, privacy/static checks and dated Simulator acceptance evidence

- [ ] **Step 1: Confirm branch, worktree and version invariants**

Run:

```bash
git branch --show-current
git status --short
rg -n 'MARKETING_VERSION =|CURRENT_PROJECT_VERSION =' ShotMarker.xcodeproj/project.pbxproj
```

Expected: branch is `codex/clip-confirmation`; status contains only intended Change work; product targets remain 1.3 / Build 3.

- [ ] **Step 2: Run all new and directly affected focused suites**

Run the exact focused command from Task 10. Expected: all listed suites pass. If any fails, fix the lowest responsible model/service boundary first, rerun that single suite, then rerun this focused group.

- [ ] **Step 3: Run the complete iPhone test suite**

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: every `ShotMarkerTests` test passes. Record exact passed/failed/skipped counts from this run; do not repeat the 189-test baseline as if it were current.

- [ ] **Step 4: Run the complete Watch test suite**

```bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarkerWatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all `ShotMarkerWatchAppTests` pass, demonstrating no shared training/sync contract regression. Record the actual count.

- [ ] **Step 5: Build Release for a generic iOS Simulator**

```bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run repository and privacy-boundary checks**

```bash
git diff --check
wc -l docs/current/*.md
rg -n 'Analytics|analytics\.track|session\.id|marker.*UUID|localIdentifier|absoluteString' \
  ShotMarker/Models/HighlightClipReview.swift \
  ShotMarker/Services/HighlightClipReviewPlanner.swift \
  ShotMarker/Services/HighlightClipReviewMediaProvider.swift \
  ShotMarker/ViewModels/HighlightClipReviewViewModel.swift \
  ShotMarker/ViewModels/HighlightClipPlaybackController.swift \
  ShotMarker/Views/HighlightClipReviewView.swift \
  ShotMarker/Views/HighlightClipEditorView.swift \
  ShotMarker/Views/HighlightClipTimelineView.swift
```

Expected: `git diff --check` exits 0; current docs are still <=300 lines before documentation edits; no new Analytics call exists. Asset resolution may legitimately mention `localIdentifier`/`absoluteString`, but log calls and context values must not contain them. Review every match rather than assuming zero matches.

- [ ] **Step 7: Perform and record the complete Simulator acceptance matrix**

Use at least iPhone 17 Pro / iOS 26.5 Simulator, one landscape video, one portrait video, one no-audio video, and a training record with adjacent markers that yields a merged card. Record the exact device/OS, media dimensions/durations and pass/fail for all flows:

1. Enter review after video preparation; verify real full-frame thumbnails, `1`/`2–3` labels and default included state.
2. Accept every default without touching cards; compare labels/initial merge with the legacy plan and compare final bounds with those same legacy bounds passed through the documented 0.1-second/timescale-600 normalization.
3. Exclude and restore both a normal and merged card; verify position, stable identity, retained edits, renumbering and all four summary values.
4. Open cards through the number and whole-card areas; both targets are at least 44×44.
5. Drag start, end, whole-range grip and playhead; verify each affects only its named state.
6. Exercise every `-0.5s`/`+0.5s` operation and compare displayed times to playback.
7. Move/edit against video start/end and minimum duration; verify clamping and understandable disabled feedback.
8. Move adjacent cards into overlap/<=1-second gap; verify merge hint, one final segment and non-duplicated duration.
9. Verify selected-range playback stops at end and returns to start; no autoplay on entry.
10. Move a card outside its fixed marker lines; verify references do not move and training data remains unchanged.
11. Change only marker-label style, return to review and verify the range draft survives.
12. Attempt video/order and before/after changes; verify confirmation precedes draft destruction and Cancel preserves it.
13. Exit the whole flow with edits; verify “放弃片段调整？” and Cancel/Confirm behavior.
14. Simulate thumbnail generation failure; verify placeholder and successful editing/confirmation when playback remains usable.
15. Remove or deny access to a source; verify included confirmation is blocked, exclusion allows remaining valid cards, and retry/return guidance is actionable.
16. Create a task, change global defaults, interrupt/restart the task and verify export uses the same confirmed ranges and captured marker style.
17. Rapidly switch cards/windows and leave the page; verify old filmstrip requests stop, playback audio stops and only one active player remains.
18. Turn on VoiceOver and complete card entry, include/exclude, both handles, whole move, playhead, all fine-tune operations, play/pause and restore default.
19. Set maximum Dynamic Type; verify single-column fallback, readable summary/status/time, no key truncation and 44-point targets.

If any flow fails, do not document completion. Add a failing automated test at the lowest testable boundary, implement the fix, rerun its focused suite plus Steps 3–6, then repeat the failed manual flow.

- [ ] **Step 8: Review final implementation diff**

```bash
git status --short
git diff --stat
git diff --check
git log --oneline --decorate -12
```

Expected: intended task commits are visible, no unrelated file was included, and no whitespace error remains. Any verification-driven code fix must receive its own Chinese `fix:` or `test:` commit before documentation closure.

---

### Task 12: 更新当前事实并归档完成的 Change

**Files:**

- Modify: `docs/README.md`
- Modify: `docs/current/product.md`
- Modify: `docs/current/architecture.md`
- Modify: `docs/current/quality.md`
- Modify: `docs/current/status.md`
- Move: `docs/changes/2026-09-02-highlight-clip-review-spec.md`
- Move: `docs/changes/2026-09-02-highlight-clip-review-plan.md`

**Interfaces:**

- Consumes: actual Task 11 automated and manual evidence
- Produces: concise implementation facts separated from effective product decisions
- Produces: completed spec and plan directly under `docs/archive/2026-09/`
- Preserves: Analytics four-event contract, 1.3/Build 3 release facts and unrelated voice-command Change

- [ ] **Step 1: Update product and architecture current facts**

In `docs/current/product.md`, replace the “尚未实现” review statement only after verification. Record:

- required page-level review with all cards default included;
- merged-card atomic include/exclude/range adjustment and fixed original markers;
- 0.1-second saved precision, 0.5-second fine tuning and final <=1-second adjacent merge;
- exact segment task snapshot across queue/restart;
- in-memory-only unconfirmed draft limitation.

In `docs/current/architecture.md`, update review date/baseline and record the verified chain:

```text
VideoClipSegmentPlanner legacy/default plan
→ HighlightClipReviewPlanner draft + final summary
→ HighlightClipReviewViewModel
→ ConfirmedHighlightSegment[] / clipPlanVersion 1
→ HighlightJobManager
→ HighlightJobRunner version routing
→ VideoClipEditingService
```

Record that media provider/player/frame caches are in-memory and cancellable, while old jobs with both optional fields absent use legacy planning. Do not describe a proposal or unverified optimization as implementation fact.

- [ ] **Step 2: Update quality and status from fresh evidence**

In `docs/current/quality.md`, record the actual date, commit/baseline, simulator model/OS, exact iPhone/Watch counts, Release build, `git diff --check`, and the manual flows that truly passed. Retain unresolved UI-test/CI/device/release limitations; a Simulator run does not become true-device or TestFlight evidence.

In `docs/current/status.md`, move clip review from “已确认但未实现” into implemented facts only if Task 11 passed. Keep the voice-command Change and external release risks unchanged.

Do not modify `docs/current/analytics.md` or `docs/current/release.md` unless Task 11 produced new facts affecting those documents. This Change intentionally adds no events and no version/release action.

- [ ] **Step 3: Verify current-document limits and fact boundaries**

```bash
wc -l docs/current/*.md
rg -n '片段审核|clipPlanVersion|confirmedSegments|1\.2|1\.3|Analytics' \
  docs/current docs/README.md
```

Expected: every current file is <=300 lines; implementation facts cite fresh evidence; 1.2/1.3 compatibility and release references are unambiguous; no text claims draft persistence, Watch UI, new Analytics or a version bump.

- [ ] **Step 4: Mark the plan result and archive both artifacts**

Add a short `**执行结果（YYYY-MM-DD）：**` paragraph under this plan’s Spec header with actual automated counts, build, manual evidence and any explicitly unverified items. Change its Spec link to:

```text
docs/archive/2026-09/2026-09-02-highlight-clip-review-spec.md
```

Remove the completed review item from `docs/README.md` 的“正在进行的变更”, preserving the voice-command item. Then move exactly these files:

```bash
mkdir -p docs/archive/2026-09
mv \
  docs/changes/2026-09-02-highlight-clip-review-spec.md \
  docs/archive/2026-09/2026-09-02-highlight-clip-review-spec.md
mv \
  docs/changes/2026-09-02-highlight-clip-review-plan.md \
  docs/archive/2026-09/2026-09-02-highlight-clip-review-plan.md
```

Verify:

```bash
rg --files docs/changes docs/archive/2026-09 | sort
```

Expected: both files are direct children of `docs/archive/2026-09/`, neither remains in `docs/changes/`, and no deeper topic directory exists.

- [ ] **Step 5: Review and commit documentation closure**

```bash
git diff --check
git status --short
git diff -- docs/README.md docs/current docs/archive/2026-09
```

Expected: current facts match Task 11 evidence, unrelated documentation is preserved, and the archived plan’s Spec link resolves.

```bash
git add \
  docs/README.md \
  docs/current/product.md \
  docs/current/architecture.md \
  docs/current/quality.md \
  docs/current/status.md \
  docs/archive/2026-09/2026-09-02-highlight-clip-review-spec.md \
  docs/archive/2026-09/2026-09-02-highlight-clip-review-plan.md
git commit -m "docs: 更新片段审核当前事实并归档变更"
```

---

## Final Verification Gate

Before declaring the Change complete, confirm all of the following evidence exists from the same final code baseline:

```bash
git branch --show-current
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarkerWatchApp \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
git diff --check
git status --short
```

Completion requires:

- branch output is `codex/clip-confirmation`;
- every new focused suite and both complete iPhone/Watch suites pass with fresh counts;
- Release generic iOS Simulator build succeeds;
- all acceptance flows in the user-confirmed final scope are recorded with exact Simulator/media details; the original VoiceOver flow was explicitly removed from scope on 2026-09-03, remains unverified and is not recorded as passed;
- default review output matches legacy planning, and all range/merge/numbering/validation cases pass;
- new jobs store version 1 exact snapshots, old 1.2/1.3 fixtures use legacy planning, and every malformed discriminator case fails without fallback;
- only final referenced temporary videos are copied, while cancellation/restart/interruption use unchanged persisted segments;
- no Watch/training/sync/Analytics/version contract changed;
- `docs/current/` reflects verified facts, each file remains <=300 lines, and both artifacts are archived under `docs/archive/2026-09/`;
- no unrelated user change was discarded or folded into a Change commit.

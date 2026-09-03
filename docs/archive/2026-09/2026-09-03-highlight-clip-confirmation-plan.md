# ShotMarker 片段确认持久化与连续审核 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为每个审核卡片增加原子持久化的逐片段确认、跨启动精确恢复、明确的编辑事务和连续审核导航，同时让未确认卡片继续按当前默认规则直接参与集锦生成。

**Architecture:** 在现有运行时视频、默认规划和任务快照之外新增三层边界：稳定审核组合身份、版本 1 JSON Store、无 UI 的确认项恢复规划。单片段编辑改为独立工作副本；审核 ViewModel 只在 Store 写入成功后发布新卡片和下一步导航，训练记录的删除、替换、合并和载入 reconciliation 通过同一个 Store 清理接口保持松耦合。

**Tech Stack:** Swift 5 language mode、SwiftUI、Combine、Photos/PhotosUI、AVFoundation/CoreMedia、CryptoKit、Foundation actor、XCTest/XCUITest、Xcode 26.6 / Swift 6.3.3 toolchain

**Spec:** `docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-spec.md`

**执行结果（2026-09-03）：** 实现代码基线 `babebb0` 的直接受影响测试 186 项、完整 iPhone scheme 342 项（含 9 项 UI 测试）和完整 Watch scheme 30 项均为 0 失败、0 跳过，generic iOS Simulator Release 构建与产物/DEBUG 入口检查通过。iPhone 17 Pro / iOS 26.5 Simulator 使用两段 640×360、H.264、无音轨、各 40 秒的视频完成普通、合并、跨视频卡片的持久化、恢复、顺序隔离、默认重算、放弃、覆盖、排除和任务清理验收；写入失败及训练生命周期清理由自动测试覆盖。VoiceOver、真机、正式 Archive、TestFlight 与线上服务未执行且不记为通过；完整证据见 [验证记录](2026-09-03-highlight-clip-confirmation-validation.md)。

## Global Constraints

- 计划基线是 main / 7084f17；执行前重新运行 git branch --show-current、git status --short 和 git rev-parse --short HEAD。不得丢弃或覆盖任何未提交的用户修改。
- 实施开始时使用 superpowers:using-git-worktrees 建立隔离工作区；如果执行环境已经是 linked worktree，则沿用当前 worktree，不建立嵌套 worktree。
- 本 Change 不修改 MARKETING_VERSION 或 CURRENT_PROJECT_VERSION；产品 target 保持 1.3（Build 3）。
- 工程保持 Swift 5 language mode、iOS 26.4 与 watchOS 26.2 部署下限；计划编写时使用 Xcode 26.6、Swift 6.3.3。
- 片段确认只写入 Application Support/ShotMarker/highlight-clip-reviews.json，根 schemaVersion 固定为 1；不得写入 TrainingSession、training-sessions.json、HighlightJob 历史、Watch 同步载荷或 UserDefaults。
- 审核组合必须比较完整训练身份与严格有序的视频身份；训练日期使用 Unix epoch 毫秒整数，视频时长使用 timescale 600 tick。全局前后时长和 MarkerLabelStyle 不进入组合身份。
- PhotoKit/PhotosPicker 有稳定资源标识时使用带类型的资源标识；只有临时文件路径才在后台以固定大小缓冲区计算完整 SHA-256。临时 URL、展示编号、随机 UUID 和摘要本身都不能代替完整组合结构。
- 已确认项的范围、默认基线和确认时间使用持久模型；显示编号、缩略图、胶片帧、播放器状态、临时 URL、保存状态和错误文案不得持久化。
- 范围继续按 0.1 秒规范化并使用 timescale 600；视频至少 1 秒时片段最短为 1 秒，更短视频只能使用完整有效范围。不得改变默认规划、最终相邻合并、导出编号和任务快照语义。
- 单片段编辑只修改工作副本。只有原子写盘成功后才更新审核图集、确认状态、汇总、缩略图和导航；保存失败必须保留工作副本和旧图集值。
- 确认成功只查找当前卡片之后的第一个默认片段，跳过已确认片段；后面没有默认片段时返回图集，不从开头循环。
- 默认卡片不是未完成项；页面级“确认并生成”不得新增全部确认门槛。已确认排除项占用其关联打点，不允许这些打点重新生成默认卡片。
- 未确认工作副本返回时必须显示“放弃本次调整？”。放弃不删除或改写旧确认项；无变化时直接返回。
- 精确范围调整使用标题“精确范围调整”的 DisclosureGroup，每次创建编辑器时默认收起且不持久化；播放预览、时间值、时间轴、播放按钮、保留状态和恢复默认范围保持常显。
- Store 写入在单一 actor 内串行；使用目标目录内临时文件和原子替换。损坏根文件先移动为 highlight-clip-reviews.corrupt-<UTC 时间戳>.json，再建立空版本 1 文档；高于 1 的 schema 不得被覆盖。
- 删除训练记录会删除相同 TrainingSession.id 的全部组合。导入替换、Watch 替换和合并只在训练保存成功后清理内容已失效的记录；清理失败不回滚训练事实，并由下次训练列表 reconciliation 重试。
- 清除、取消、失败、完成或重启 HighlightJob 不得删除片段确认记录；不修改 HighlightJob fixture、Runner 版本路由或 clipPlanVersion = 1 契约。
- 不增加 Analytics 事件、远端字段、GlitchTip metadata 或业务上传。日志不得包含 PhotoKit local identifier、内容 SHA-256、训练/打点 UUID、临时路径或媒体内容，只记录封闭错误类别与数量。
- 图集和编辑器状态必须有独立可访问文本，不能只靠颜色；关键入口和底部按钮至少 44×44 点，最大 Dynamic Type 下允许换行且保持可操作。
- 工程使用 PBXFileSystemSynchronizedRootGroup；新增 Swift 和测试文件放入现有 ShotMarker、ShotMarkerTests 或 ShotMarkerUITests 目录即可进入对应 target，不手工增加 PBX file reference。
- 每个实现提交使用中文 Conventional Commit 备注，例如 feat: 增加片段确认身份、fix: 保证确认原子发布、test: 补充片段恢复回归、docs: 更新片段确认当前事实。
- 完成时必须用 fresh evidence 更新 docs/current/，再把本 spec、plan 和实际验收记录移入 docs/archive/2026-09/；不得把未执行的 VoiceOver、真机、TestFlight 或外部服务流程写成已通过。
- 公共验收记录只写 Simulator 型号与 OS；若本次额外执行真机、Archive、TestFlight、App Store Connect、Analytics production 或 GlitchTip production 验证，其权威事实写入已同步且干净的 docs/private.local/shotmarker/，公共仓库只保留不含 UDID、账号或测试者信息的必要摘要。

## File Map

### Create

- ShotMarker/Models/HighlightClipReviewPersistence.swift：完整训练/视频组合身份、组合摘要键、版本 1 根文档、组合记录和持久确认项。
- ShotMarker/Services/HighlightClipReviewIdentityBuilder.swift：毫秒/tick 规范化、稳定排序、完整组合构建和确定性 SHA-256 索引。
- ShotMarker/Services/HighlightClipReviewContentHasher.swift：临时视频的后台分块 SHA-256。
- ShotMarker/Services/HighlightClipReviewStore.swift：HighlightClipReviewStoring protocol、actor 磁盘实现、内存实现、损坏恢复、未知版本保护、原子 upsert、删除和 reconciliation。
- ShotMarker/Services/HighlightClipReviewRestoration.swift：HighlightClipReviewPlanner 的纯恢复扩展；验证确认项、占用打点、重建剩余默认卡片和稳定交错。
- ShotMarker/ViewModels/HighlightClipEditorViewModel.swift：单片段工作副本、脏状态、保存状态、错误和确认回调。
- ShotMarker/Views/HighlightClipConfirmationUITestHarnessView.swift：仅 DEBUG 的确认状态、事务和连续导航 UI 测试入口。
- ShotMarkerTests/HighlightClipReviewIdentityBuilderTests.swift：完整组合匹配与规范化测试。
- ShotMarkerTests/HighlightClipReviewContentHasherTests.swift：分块摘要与失败测试。
- ShotMarkerTests/HighlightClipReviewStoreTests.swift：文件、版本、原子写入、并发、删除和 reconciliation 测试。
- ShotMarkerTests/HighlightClipReviewRestorationTests.swift：确认项与默认项恢复合并测试。
- ShotMarkerTests/HighlightClipEditorViewModelTests.swift：工作副本、放弃、保存和重复提交测试。
- ShotMarkerUITests/HighlightClipConfirmationUITests.swift：状态文案、折叠、放弃提示、连续导航和 Dynamic Type 测试。
- docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-validation.md：完成阶段写入实际 Simulator/设备、系统版本、命令、计数与人工结果。

### Modify

- ShotMarker/Services/VideoClipSegmentPlanner.swift:8-16,130-146：让 SelectedTrainingVideo 同时携带运行时 ID 与可选稳定审核身份，并给同时间打点增加 UUID 稳定次序。
- ShotMarker/Models/HighlightClipReview.swift:17-44,57-69：加入默认/已确认状态与恢复提示值。
- ShotMarker/Services/TrainingVideoLoadingService.swift:6-14,170-233：PhotoKit 路径注入资源身份，临时文件路径只计算一次内容摘要并保存在 SelectedTrainingVideo。
- ShotMarker/Services/HighlightClipReviewPlanner.swift:89-143,360-362：向恢复扩展开放规范化检查，不改变现有汇总与任务快照逻辑。
- ShotMarker/ViewModels/HighlightClipReviewViewModel.swift:13-189,248-341,502-512：移除共享卡片的直接编辑，加入 Store 成功后的确认发布、编辑器工厂和下一默认片段规则。
- ShotMarker/Views/HighlightClipEditorView.swift:4-92,94-445：改读工作副本，增加状态、默认收起 DisclosureGroup、固定确认按钮、保存错误和放弃提示。
- ShotMarker/Views/HighlightClipReviewView.swift:5-73,143-245,282-380：显示默认/已确认/不可用状态，持有编辑器事务目标并消费确认导航。
- ShotMarker/Views/TrainingSessionHighlightView.swift:8-194,235-309,376-393,827-1015：异步加载组合记录与恢复草稿，注入 Store，并移除会把已确认数据误称为未保存草稿的旧提示。
- ShotMarker/ShotMarkerApp.swift:13-108、ShotMarker/ContentView.swift:10-43、ShotMarker/Views/TrainingSessionListView.swift:55-123,363-369：构造并向审核与训练变更链路传递同一个 Store。
- ShotMarker/Services/TrainingSessionImporter.swift:3-32、ShotMarker/Services/TrainingSessionJSONTransferService.swift:23-78：训练保存成功后等待内容变化清理，清理失败只记录并允许下次 reconciliation。
- ShotMarker/ViewModels/TrainingSessionListViewModel.swift:42-240、ShotMarker/Views/TrainingSessionListView.swift:108-178,236-296,422-430,559-604：异步载入 reconciliation、删除/合并/导入清理以及缺失的训练删除入口。
- ShotMarker/Services/PhoneWatchSyncService.swift:34-71,112-207：等待异步 importer 后再发送现有 ACK，不修改载荷或 Analytics 事件。
- ShotMarkerTests/TrainingVideoLoadingServiceTests.swift、ShotMarkerTests/HighlightClipReviewPlannerTests.swift、ShotMarkerTests/HighlightClipReviewViewModelTests.swift：适配稳定身份、确认状态与工作副本边界。
- ShotMarkerTests/TrainingSessionImporterTests.swift、ShotMarkerTests/TrainingSessionJSONTransferServiceTests.swift、ShotMarkerTests/TrainingSessionListViewModelTests.swift、ShotMarkerTests/PhoneWatchSyncServiceTests.swift：覆盖替换、删除、合并、reconciliation 和 ACK 时序。
- ShotMarker/ShotMarkerApp.swift、ShotMarkerUITests/HighlightClipTimelineUITests.swift：保留现有 DEBUG 时间轴入口并增加独立确认流程入口；Release 中两个入口都必须不可见。
- docs/README.md、docs/current/product.md、docs/current/architecture.md、docs/current/quality.md、docs/current/status.md：完成实际验证后更新当前事实和 Change 状态。

### Archive after verified completion

- docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-spec.md
- docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-plan.md
- docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-validation.md

---

### Task 1: 建立版本 1 持久化模型与完整组合身份

**Files:**

- Create: ShotMarker/Models/HighlightClipReviewPersistence.swift
- Create: ShotMarker/Services/HighlightClipReviewIdentityBuilder.swift
- Create: ShotMarkerTests/HighlightClipReviewIdentityBuilderTests.swift
- Modify: ShotMarker/Services/VideoClipSegmentPlanner.swift:8-16,130-146
- Modify: ShotMarker/Models/HighlightClipReview.swift:17-44

**Interfaces:**

- Produces: HighlightClipReviewSourceIdentity(kind:value:)
- Produces: HighlightClipReviewTrainingIdentity(id:startedAtMilliseconds:endedAtMilliseconds:markers:)
- Produces: HighlightClipReviewVideoIdentity(source:recordedStartAtMilliseconds:durationTicks:)
- Produces: HighlightClipReviewCombination(training:videos:)
- Produces: HighlightClipReviewCombinationKey(digest:combination:)
- Produces: HighlightClipReviewIdentityBuilder.trainingIdentity(for:)、videoIdentity(for:) 和 combinationKey(for:videos:)
- Changes: SelectedTrainingVideo.init(id:recordedStartAt:duration:reviewSourceIdentity:)；最后一个参数默认 nil，只允许不参与审核持久化的旧任务/测试省略。
- Changes: HighlightClipReviewItem.confirmationState，默认值为 .defaultValue。
- Consumes later: Store、恢复规划和 ViewModel 只使用本任务定义的完整组合与稳定来源身份。

- [ ] **Step 1: Write failing identity and normalization tests**

Create ShotMarkerTests/HighlightClipReviewIdentityBuilderTests.swift。固定 UUID、日期和视频元数据，加入以下可编译测试；makeSession、makeVideo 和 source(_:) 由同文件私有 helper 返回确定值。

~~~swift
@testable import ShotMarker
import XCTest

final class HighlightClipReviewIdentityBuilderTests: XCTestCase {
    func testIdenticalTrainingAndOrderedVideosProduceIdenticalKey() throws {
        let session = makeSession()
        let videos = [
            makeVideo(id: "runtime-a", source: source("asset-a"), start: 100, duration: 60),
            makeVideo(id: "runtime-b", source: source("asset-b"), start: 160, duration: 45),
        ]

        XCTAssertEqual(
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: videos),
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: videos),
        )
    }

    func testVideoOrderChangesCombination() throws {
        let session = makeSession()
        let first = makeVideo(id: "a", source: source("asset-a"), start: 100, duration: 60)
        let second = makeVideo(id: "b", source: source("asset-b"), start: 160, duration: 45)

        XCTAssertNotEqual(
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [first, second]),
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [second, first]),
        )
    }

    func testTrainingContentChangesCombinationEvenWhenIDMatches() throws {
        let original = makeSession()
        let changedStart = TrainingSession(
            id: original.id,
            startedAt: original.startedAt.addingTimeInterval(0.001),
            endedAt: original.endedAt,
            events: original.events,
        )
        let changedMarker = TrainingSession(
            id: original.id,
            startedAt: original.startedAt,
            endedAt: original.endedAt,
            events: [
                ShotMarkerEvent(id: original.events[0].id,
                                markedAt: original.events[0].markedAt.addingTimeInterval(0.001)),
            ],
        )
        let changedMarkerID = TrainingSession(
            id: original.id,
            startedAt: original.startedAt,
            endedAt: original.endedAt,
            events: [
                ShotMarkerEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                    markedAt: original.events[0].markedAt,
                ),
            ],
        )
        let videos = [makeVideo()]

        let key = try HighlightClipReviewIdentityBuilder.combinationKey(for: original, videos: videos)
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: changedStart, videos: videos))
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: changedMarker, videos: videos))
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: changedMarkerID, videos: videos))
    }

    func testMetadataAndSourceChangesCombination() throws {
        let session = makeSession()
        let base = makeVideo()
        let changedSource = makeVideo(source: source("different"))
        let changedDate = makeVideo(start: 100.001)
        let changedDuration = makeVideo(duration: 60.01)
        let key = try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [base])

        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [changedSource]))
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [changedDate]))
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [changedDuration]))
    }

    func testMillisecondAndSixHundredTickNormalizationRemoveTailNoise() throws {
        let session = makeSession(startedAt: 10.000_000_1)
        let noisySession = makeSession(startedAt: 10.000_000_2)
        let video = makeVideo(start: 100.000_000_1, duration: 60.000_000_1)
        let noisyVideo = makeVideo(start: 100.000_000_2, duration: 60.000_000_2)

        XCTAssertEqual(
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [video]),
            try HighlightClipReviewIdentityBuilder.combinationKey(for: noisySession, videos: [noisyVideo]),
        )
    }

    func testMarkerTieUsesUUIDAndVideoOrderRemainsUnsorted() throws {
        let date = Date(timeIntervalSince1970: 20)
        let high = ShotMarkerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            markedAt: date,
        )
        let low = ShotMarkerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            markedAt: date,
        )
        let session = TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            startedAt: date,
            endedAt: date.addingTimeInterval(5),
            events: [high, low],
        )

        let identity = HighlightClipReviewIdentityBuilder.trainingIdentity(for: session)
        XCTAssertEqual(identity.markers.map(\.id), [low.id, high.id])
    }

    func testSettingsAndLabelStyleAreNotCombinationInputs() throws {
        let session = makeSession()
        let videos = [makeVideo()]
        let key = try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: videos)
        var settings = ClipSettings.default
        settings.secondsBeforeMarker = 20
        settings.secondsAfterMarker = 20

        XCTAssertNotEqual(settings, .default)
        XCTAssertEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: videos))
    }

    func testMissingStableSourceIdentityRejectsCombination() {
        let video = SelectedTrainingVideo(
            id: "file:///temporary.mov",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        XCTAssertThrowsError(
            try HighlightClipReviewIdentityBuilder.combinationKey(for: makeSession(), videos: [video]),
        ) {
            XCTAssertEqual($0 as? HighlightClipReviewIdentityError, .missingSourceIdentity)
        }
    }

    func testDuplicateCompleteVideoIdentityIsRejectedEvenWhenRuntimeIDsDiffer() {
        let source = HighlightClipReviewSourceIdentity.photoLibraryAsset("same-asset")
        let videos = [
            makeVideo(id: "runtime-a", source: source, start: 100),
            makeVideo(id: "runtime-b", source: source, start: 100),
        ]

        XCTAssertThrowsError(
            try HighlightClipReviewIdentityBuilder.combinationKey(
                for: makeSession(),
                videos: videos,
            ),
        ) {
            XCTAssertEqual($0 as? HighlightClipReviewIdentityError, .duplicateVideoIdentity)
        }
    }
}

private extension HighlightClipReviewIdentityBuilderTests {
    func source(_ value: String) -> HighlightClipReviewSourceIdentity {
        .photoLibraryAsset(value)
    }

    func makeVideo(
        id: String = "runtime-video",
        source: HighlightClipReviewSourceIdentity = .photoLibraryAsset("asset-a"),
        start: TimeInterval = 100,
        duration: TimeInterval = 60,
    ) -> SelectedTrainingVideo {
        SelectedTrainingVideo(
            id: id,
            recordedStartAt: Date(timeIntervalSince1970: start),
            duration: duration,
            reviewSourceIdentity: source,
        )
    }

    func makeSession(startedAt: TimeInterval = 10) -> TrainingSession {
        let start = Date(timeIntervalSince1970: startedAt)
        return TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            events: [
                ShotMarkerEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                    markedAt: start.addingTimeInterval(20),
                ),
            ],
        )
    }
}
~~~

- [ ] **Step 2: Run the focused test and verify the expected compile failure**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewIdentityBuilderTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: FAIL because the persistence identity types and builder do not exist.

- [ ] **Step 3: Add the exact Codable identity and store value model**

Create ShotMarker/Models/HighlightClipReviewPersistence.swift with these stored fields. Keep raw local identifiers and digests private to this data layer; do not add CustomStringConvertible.

~~~swift
import Foundation

struct HighlightClipReviewSourceIdentity: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case photoLibraryAsset
        case fileSHA256
    }

    let kind: Kind
    let value: String

    static func photoLibraryAsset(_ value: String) -> Self {
        Self(kind: .photoLibraryAsset, value: value)
    }

    static func fileSHA256(_ value: String) -> Self {
        Self(kind: .fileSHA256, value: value)
    }
}

struct HighlightClipReviewMarkerIdentity: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let markedAtMilliseconds: Int64
}

struct HighlightClipReviewTrainingIdentity: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let startedAtMilliseconds: Int64
    let endedAtMilliseconds: Int64
    let markers: [HighlightClipReviewMarkerIdentity]
}

struct HighlightClipReviewVideoIdentity: Codable, Equatable, Hashable, Sendable {
    let source: HighlightClipReviewSourceIdentity
    let recordedStartAtMilliseconds: Int64
    let durationTicks: Int64
}

struct HighlightClipReviewCombination: Codable, Equatable, Hashable, Sendable {
    let training: HighlightClipReviewTrainingIdentity
    let videos: [HighlightClipReviewVideoIdentity]
}

struct HighlightClipReviewCombinationKey: Equatable, Hashable, Sendable {
    let digest: String
    let combination: HighlightClipReviewCombination
}

struct HighlightClipReviewStoreDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var records: [PersistedHighlightClipReview]

    static let empty = Self(schemaVersion: currentSchemaVersion, records: [])
}

struct PersistedHighlightClipReview: Codable, Equatable, Sendable {
    let combinationDigest: String
    let combination: HighlightClipReviewCombination
    var confirmedItems: [PersistedHighlightClipConfirmation]
    let createdAt: Date
    var updatedAt: Date
}

struct PersistedHighlightClipConfirmation: Codable, Equatable, Sendable {
    let videoIdentity: HighlightClipReviewVideoIdentity
    let markerIDs: [UUID]
    let defaultStart: TimeInterval
    let defaultDuration: TimeInterval
    let start: TimeInterval
    let duration: TimeInterval
    let isIncluded: Bool
    let confirmedAt: Date

    var identity: HighlightClipConfirmationIdentity {
        HighlightClipConfirmationIdentity(videoIdentity: videoIdentity, markerIDs: markerIDs)
    }
}

struct HighlightClipConfirmationIdentity: Equatable, Hashable, Sendable {
    let videoIdentity: HighlightClipReviewVideoIdentity
    let markerIDs: [UUID]
}
~~~

- [ ] **Step 4: Give runtime videos and review cards explicit dual identities**

Modify SelectedTrainingVideo in ShotMarker/Services/VideoClipSegmentPlanner.swift so old task playback can omit the review identity but combination construction cannot:

~~~swift
struct SelectedTrainingVideo: Identifiable, Equatable {
    let id: String
    let recordedStartAt: Date
    let duration: TimeInterval
    let reviewSourceIdentity: HighlightClipReviewSourceIdentity?

    init(
        id: String,
        recordedStartAt: Date,
        duration: TimeInterval,
        reviewSourceIdentity: HighlightClipReviewSourceIdentity? = nil,
    ) {
        self.id = id
        self.recordedStartAt = recordedStartAt
        self.duration = duration
        self.reviewSourceIdentity = reviewSourceIdentity
    }

    var recordedEndAt: Date {
        recordedStartAt.addingTimeInterval(duration)
    }
}
~~~

Modify ShotMarker/Models/HighlightClipReview.swift:

~~~swift
enum HighlightClipConfirmationState: Equatable {
    case defaultValue
    case confirmed
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
    var confirmationState: HighlightClipConfirmationState

    init(
        id: UUID,
        videoID: String,
        markerReferences: [HighlightClipMarkerReference],
        defaultStart: TimeInterval,
        defaultDuration: TimeInterval,
        start: TimeInterval,
        duration: TimeInterval,
        isIncluded: Bool,
        confirmationState: HighlightClipConfirmationState = .defaultValue,
    ) {
        self.id = id
        self.videoID = videoID
        self.markerReferences = markerReferences
        self.defaultStart = defaultStart
        self.defaultDuration = defaultDuration
        self.start = start
        self.duration = duration
        self.isIncluded = isIncluded
        self.confirmationState = confirmationState
    }

    var range: HighlightClipRange {
        HighlightClipRange(start: start, duration: duration)
    }

    var defaultRange: HighlightClipRange {
        HighlightClipRange(start: defaultStart, duration: defaultDuration)
    }

    var originalNumberRange: ClosedRange<Int>? {
        guard let first = markerReferences.first,
              let last = markerReferences.last
        else {
            return nil
        }
        return first.originalMatchedNumber ... last.originalMatchedNumber
    }
}
~~~

Use this explicit initializer so existing call sites retain source compatibility through the final default argument. Do not derive confirmation state from isIncluded.

- [ ] **Step 5: Implement canonical identity construction and deterministic digesting**

Create ShotMarker/Services/HighlightClipReviewIdentityBuilder.swift:

~~~swift
import CoreMedia
import CryptoKit
import Foundation

enum HighlightClipReviewIdentityError: LocalizedError, Equatable {
    case missingSourceIdentity
    case invalidVideoMetadata
    case duplicateVideoIdentity

    var errorDescription: String? {
        switch self {
        case .missingSourceIdentity:
            "无法建立视频的稳定身份，请重新选择视频。"
        case .invalidVideoMetadata:
            "视频时间信息无效，请重新选择视频。"
        case .duplicateVideoIdentity:
            "选择的视频身份重复，请移除重复视频后再试。"
        }
    }
}

enum HighlightClipReviewIdentityBuilder {
    static let videoTimescale: CMTimeScale = 600

    static func trainingIdentity(for session: TrainingSession) -> HighlightClipReviewTrainingIdentity {
        let markers = session.events
            .sorted {
                if $0.markedAt == $1.markedAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.markedAt < $1.markedAt
            }
            .map {
                HighlightClipReviewMarkerIdentity(
                    id: $0.id,
                    markedAtMilliseconds: milliseconds($0.markedAt),
                )
            }
        return HighlightClipReviewTrainingIdentity(
            id: session.id,
            startedAtMilliseconds: milliseconds(session.startedAt),
            endedAtMilliseconds: milliseconds(session.endedAt),
            markers: markers,
        )
    }

    static func combinationKey(
        for session: TrainingSession,
        videos: [SelectedTrainingVideo],
    ) throws -> HighlightClipReviewCombinationKey {
        let videoIdentities = try videos.map(videoIdentity(for:))
        guard Set(videoIdentities).count == videoIdentities.count else {
            throw HighlightClipReviewIdentityError.duplicateVideoIdentity
        }

        let combination = HighlightClipReviewCombination(
            training: trainingIdentity(for: session),
            videos: videoIdentities,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(combination)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return HighlightClipReviewCombinationKey(digest: digest, combination: combination)
    }

    static func videoIdentity(
        for video: SelectedTrainingVideo,
    ) throws -> HighlightClipReviewVideoIdentity {
        guard let source = video.reviewSourceIdentity else {
            throw HighlightClipReviewIdentityError.missingSourceIdentity
        }
        guard video.duration.isFinite, video.duration > 0 else {
            throw HighlightClipReviewIdentityError.invalidVideoMetadata
        }
        return HighlightClipReviewVideoIdentity(
            source: source,
            recordedStartAtMilliseconds: milliseconds(video.recordedStartAt),
            durationTicks: CMTime(
                seconds: video.duration,
                preferredTimescale: videoTimescale,
            ).value,
        )
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.toNearestOrAwayFromZero))
    }
}
~~~

Update VideoClipSegmentPlanner.highlightPlan so equal markedAt values compare event UUID strings. This aligns default planning with the combination identity without changing ordinary chronological behavior.

- [ ] **Step 6: Run identity and existing planner tests**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewIdentityBuilderTests \
  -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS. Existing SelectedTrainingVideo call sites compile through the default nil argument; identity tests explicitly provide a stable source identity.

- [ ] **Step 7: Commit the identity boundary**

~~~bash
git add \
  ShotMarker/Models/HighlightClipReviewPersistence.swift \
  ShotMarker/Models/HighlightClipReview.swift \
  ShotMarker/Services/HighlightClipReviewIdentityBuilder.swift \
  ShotMarker/Services/VideoClipSegmentPlanner.swift \
  ShotMarkerTests/HighlightClipReviewIdentityBuilderTests.swift
git commit -m "feat: 增加片段确认组合身份"
~~~

---

### Task 2: 流式计算临时视频身份并接入视频准备

**Files:**

- Create: ShotMarker/Services/HighlightClipReviewContentHasher.swift
- Create: ShotMarkerTests/HighlightClipReviewContentHasherTests.swift
- Modify: ShotMarker/Services/TrainingVideoLoadingService.swift:170-233
- Modify: ShotMarkerTests/TrainingVideoLoadingServiceTests.swift

**Interfaces:**

- Produces: HighlightClipReviewContentHashing.sha256(for:)
- Produces: HighlightClipReviewContentHasher(chunkSize:readChunk:)
- Changes: TrainingVideoLoadingService.live(photoLibraryAssetProvider:temporaryFileStore:contentHasher:)
- Guarantees: PhotoKit 分支不调用内容哈希；临时文件分支完成一次哈希后把结果存在 SelectedTrainingVideo.reviewSourceIdentity。
- Consumes: Task 1 的 HighlightClipReviewSourceIdentity。

- [ ] **Step 1: Write failing bounded-buffer digest tests**

Create ShotMarkerTests/HighlightClipReviewContentHasherTests.swift:

~~~swift
@testable import ShotMarker
import CryptoKit
import XCTest

final class HighlightClipReviewContentHasherTests: XCTestCase {
    func testSameBytesProduceSameLowercaseSHA256AndDifferentBytesDoNot() async throws {
        let firstURL = try makeFile(bytes: Data("same-content".utf8))
        let secondURL = try makeFile(bytes: Data("same-content".utf8))
        let differentURL = try makeFile(bytes: Data("different-content".utf8))
        let hasher = HighlightClipReviewContentHasher(chunkSize: 4)

        let first = try await hasher.sha256(for: firstURL)
        let second = try await hasher.sha256(for: secondURL)
        let different = try await hasher.sha256(for: differentURL)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(first, first.lowercased())
    }

    func testReaderNeverReceivesMoreThanConfiguredChunkSize() async throws {
        let fileURL = try makeFile(bytes: Data(repeating: 0x5a, count: 25))
        let lock = NSLock()
        var requestedCounts: [Int] = []
        let hasher = HighlightClipReviewContentHasher(
            chunkSize: 7,
            readChunk: { handle, count in
                lock.lock()
                requestedCounts.append(count)
                lock.unlock()
                return try handle.read(upToCount: count)
            },
        )

        _ = try await hasher.sha256(for: fileURL)

        XCTAssertFalse(requestedCounts.isEmpty)
        XCTAssertTrue(requestedCounts.allSatisfy { $0 == 7 })
    }

    func testReadFailurePropagatesWithoutReturningPartialDigest() async {
        let fileURL = try! makeFile(bytes: Data("bytes".utf8))
        let hasher = HighlightClipReviewContentHasher(
            chunkSize: 4,
            readChunk: { _, _ in throw TestError.readFailed },
        )

        await XCTAssertThrowsErrorAsync(try await hasher.sha256(for: fileURL)) {
            XCTAssertEqual($0 as? TestError, .readFailed)
        }
    }
}
~~~

Add `makeFile` as a private extension of the test case, and keep the async assertion/error at file scope so every symbol above is defined in this file:

~~~swift
private extension HighlightClipReviewContentHasherTests {
    func makeFile(bytes: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("video.mov")
        try bytes.write(to: fileURL)
        return fileURL
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw")
    } catch {
        errorHandler(error)
    }
}

private enum TestError: Error, Equatable {
    case readFailed
}
~~~

- [ ] **Step 2: Run the hasher test and verify it fails**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewContentHasherTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: FAIL because HighlightClipReviewContentHasher does not exist.

- [ ] **Step 3: Implement a detached, cancellable chunk loop**

Create ShotMarker/Services/HighlightClipReviewContentHasher.swift:

~~~swift
import CryptoKit
import Foundation

protocol HighlightClipReviewContentHashing: Sendable {
    func sha256(for fileURL: URL) async throws -> String
}

struct HighlightClipReviewContentHasher: HighlightClipReviewContentHashing, @unchecked Sendable {
    typealias ReadChunk = (FileHandle, Int) throws -> Data?

    private let chunkSize: Int
    private let readChunk: ReadChunk

    init(
        chunkSize: Int = 1_048_576,
        readChunk: @escaping ReadChunk = { handle, count in
            try handle.read(upToCount: count)
        },
    ) {
        precondition(chunkSize > 0)
        self.chunkSize = chunkSize
        self.readChunk = readChunk
    }

    func sha256(for fileURL: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            var digest = SHA256()
            while true {
                try Task.checkCancellation()
                guard let data = try readChunk(handle, chunkSize), !data.isEmpty else {
                    break
                }
                digest.update(data: data)
            }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
~~~

The closure is injectable only to prove the requested read size and error path; production uses FileHandle.read(upToCount:). Do not log fileURL or the returned digest.

- [ ] **Step 4: Write video-source selection tests before changing the live loader**

Add pure helper tests to ShotMarkerTests/TrainingVideoLoadingServiceTests.swift. Refactor the live extension to expose one internal constructor rather than attempting to instantiate PhotosPickerItem in unit tests:

~~~swift
func testPhotoLibraryVideoUsesAssetIdentityWithoutHashing() async throws {
    let metadata = TrainingVideoMetadata(
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )
    let hasher = SpyContentHasher(result: .failure(TestError.unexpectedHash))

    let video = try await TrainingVideoLoadingService<PhotosPickerItem>.makeReviewIdentifiedVideo(
        runtimeID: "asset-1",
        photoLibraryIdentifier: "asset-1",
        temporaryFileURL: URL(fileURLWithPath: "/tmp/fallback-copy.mov"),
        metadata: metadata,
        contentHasher: hasher,
    )

    XCTAssertEqual(video.id, "asset-1")
    XCTAssertEqual(video.reviewSourceIdentity, .photoLibraryAsset("asset-1"))
    XCTAssertEqual(hasher.callCount, 0)
}

func testPickedFileUsesContentDigestAndKeepsRuntimeURLSeparate() async throws {
    let url = URL(fileURLWithPath: "/tmp/runtime-copy.mov")
    let hasher = SpyContentHasher(result: .success(String(repeating: "a", count: 64)))

    let video = try await TrainingVideoLoadingService<PhotosPickerItem>.makeReviewIdentifiedVideo(
        runtimeID: url.absoluteString,
        photoLibraryIdentifier: nil,
        temporaryFileURL: url,
        metadata: TrainingVideoMetadata(
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        ),
        contentHasher: hasher,
    )

    XCTAssertEqual(video.id, url.absoluteString)
    XCTAssertEqual(video.reviewSourceIdentity, .fileSHA256(String(repeating: "a", count: 64)))
    XCTAssertEqual(hasher.callCount, 1)
}

func testTemporaryRuntimeURLDoesNotChangeStableFileIdentity() async throws {
    let digest = String(repeating: "b", count: 64)
    let hasher = SpyContentHasher(result: .success(digest))
    let metadata = TrainingVideoMetadata(
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )
    let firstURL = URL(fileURLWithPath: "/tmp/runtime-copy-a.mov")
    let secondURL = URL(fileURLWithPath: "/tmp/runtime-copy-b.mov")

    let first = try await TrainingVideoLoadingService<PhotosPickerItem>.makeReviewIdentifiedVideo(
        runtimeID: firstURL.absoluteString,
        photoLibraryIdentifier: nil,
        temporaryFileURL: firstURL,
        metadata: metadata,
        contentHasher: hasher,
    )
    let second = try await TrainingVideoLoadingService<PhotosPickerItem>.makeReviewIdentifiedVideo(
        runtimeID: secondURL.absoluteString,
        photoLibraryIdentifier: nil,
        temporaryFileURL: secondURL,
        metadata: metadata,
        contentHasher: hasher,
    )

    XCTAssertNotEqual(first.id, second.id)
    XCTAssertEqual(first.reviewSourceIdentity, second.reviewSourceIdentity)
    XCTAssertEqual(hasher.callCount, 2)
}

func testPickedFileHashFailureRemovesRuntimeCopyAndReturnsNoVideo() async {
    let url = URL(fileURLWithPath: "/tmp/runtime-copy.mov")
    let hasher = SpyContentHasher(result: .failure(TestError.readFailed))
    let removals = URLRemovalRecorder()

    await XCTAssertThrowsErrorAsync(
        try await TrainingVideoLoadingService<PhotosPickerItem>.makePickedReviewVideo(
            url: url,
            metadata: TrainingVideoMetadata(
                recordedStartAt: Date(timeIntervalSince1970: 100),
                duration: 60,
            ),
            contentHasher: hasher,
            removeTemporaryVideo: removals.record,
        ),
    ) {
        XCTAssertEqual($0 as? TestError, .readFailed)
    }
    XCTAssertEqual(hasher.callCount, 1)
    XCTAssertEqual(removals.urls, [url])
}
~~~

Add this lock-protected test helper:

~~~swift
private final class SpyContentHasher: HighlightClipReviewContentHashing, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<String, TestError>
    private var calls = 0

    init(result: Result<String, TestError>) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func sha256(for _: URL) async throws -> String {
        try recordCall().get()
    }

    private func recordCall() -> Result<String, TestError> {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return result
    }
}

private final class URLRemovalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func record(_ url: URL) {
        lock.lock()
        values.append(url)
        lock.unlock()
    }
}

private enum TestError: Error, Equatable {
    case readFailed
    case unexpectedHash
}
~~~

- [ ] **Step 5: Inject stable identities in the two live loading branches**

In TrainingVideoLoadingService.live:

~~~swift
static func live(
    photoLibraryAssetProvider: PhotoLibraryVideoAssetProvider,
    temporaryFileStore: TrainingVideoTemporaryFileStore,
    contentHasher: any HighlightClipReviewContentHashing = HighlightClipReviewContentHasher(),
) -> TrainingVideoLoadingService<PhotosPickerItem>
~~~

Use this helper:

~~~swift
static func makeReviewIdentifiedVideo(
    runtimeID: String,
    photoLibraryIdentifier: String?,
    temporaryFileURL: URL?,
    metadata: TrainingVideoMetadata,
    contentHasher: any HighlightClipReviewContentHashing,
) async throws -> SelectedTrainingVideo {
    let sourceIdentity: HighlightClipReviewSourceIdentity
    if let photoLibraryIdentifier {
        sourceIdentity = .photoLibraryAsset(photoLibraryIdentifier)
    } else {
        guard let temporaryFileURL else {
            throw HighlightClipReviewIdentityError.missingSourceIdentity
        }
        sourceIdentity = .fileSHA256(
            try await contentHasher.sha256(for: temporaryFileURL),
        )
    }
    return SelectedTrainingVideo(
        id: runtimeID,
        recordedStartAt: metadata.recordedStartAt,
        duration: metadata.duration,
        reviewSourceIdentity: sourceIdentity,
    )
}

static func makePickedReviewVideo(
    url: URL,
    metadata: TrainingVideoMetadata,
    contentHasher: any HighlightClipReviewContentHashing,
    removeTemporaryVideo: (URL) -> Void,
) async throws -> SelectedTrainingVideo {
    do {
        return try await makeReviewIdentifiedVideo(
            runtimeID: url.absoluteString,
            photoLibraryIdentifier: nil,
            temporaryFileURL: url,
            metadata: metadata,
            contentHasher: contentHasher,
        )
    } catch {
        removeTemporaryVideo(url)
        throw error
    }
}
~~~

Call makeReviewIdentifiedVideo only after PhotoKit metadata succeeds, passing the local identifier and nil file URL. After picker-file metadata succeeds, call makePickedReviewVideo with temporaryFileStore.removeTemporaryVideo(at:) so hashing failures delete the copy. Retain the result on SelectedTrainingVideo so no card, thumbnail, editor or Store operation re-hashes that file.

- [ ] **Step 6: Run hasher and video loading regressions**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewContentHasherTests \
  -only-testing:ShotMarkerTests/TrainingVideoLoadingServiceTests \
  -only-testing:ShotMarkerTests/TrainingVideoTemporaryFileStoreTests \
  -only-testing:ShotMarkerTests/PhotoLibraryVideoAssetProviderTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS, including the assertion that PhotoKit never invokes the content hasher and temporary failure removes the copied file.

- [ ] **Step 7: Commit stable video preparation**

~~~bash
git add \
  ShotMarker/Services/HighlightClipReviewContentHasher.swift \
  ShotMarker/Services/TrainingVideoLoadingService.swift \
  ShotMarkerTests/HighlightClipReviewContentHasherTests.swift \
  ShotMarkerTests/TrainingVideoLoadingServiceTests.swift
git commit -m "feat: 生成视频稳定审核身份"
~~~

---

### Task 3: 实现版本保护、损坏恢复与原子 Store

**Files:**

- Create: ShotMarker/Services/HighlightClipReviewStore.swift
- Create: ShotMarkerTests/HighlightClipReviewStoreTests.swift

**Interfaces:**

- Produces: HighlightClipReviewStoring.loadRecord(for:)
- Produces: HighlightClipReviewStoring.upsert(_:for:now:)
- Produces: HighlightClipReviewStoring.deleteRecords(forTrainingSessionID:)
- Produces: HighlightClipReviewStoring.reconcile(validTrainingIdentities:)
- Produces: FileHighlightClipReviewStore actor 和 InMemoryHighlightClipReviewStore actor。
- Produces: HighlightClipReviewStoreLoadResult(record:notice:) 与 HighlightClipReviewStoreNotice。
- Test support: InMemoryHighlightClipReviewStore exposes upsertCount、deletedTrainingSessionIDs、lastValidTrainingIdentities 和 confirmations(for:) as actor-isolated read APIs.
- Guarantees: 摘要命中后仍比较完整 combination；未知版本读取为空但写入报错且原字节不变。

- [ ] **Step 1: Write failing file and schema tests**

Create ShotMarkerTests/HighlightClipReviewStoreTests.swift with a unique temporary directory per test and deterministic key/confirmation helpers. Add these first tests:

~~~swift
func testMissingFileLoadsAsEmptyVersionOneStore() async throws {
    let fixture = makeFixture()
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

    let result = try await store.loadRecord(for: fixture.key)

    XCTAssertNil(result.record)
    XCTAssertNil(result.notice)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
}

func testDigestCollisionDoesNotBypassCompleteStructureComparison() async throws {
    let fixture = makeFixture()
    let firstKey = fixture.key
    let different = HighlightClipReviewCombinationKey(
        digest: firstKey.digest,
        combination: makeDifferentCombination(from: firstKey.combination),
    )
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
    try await store.upsert(fixture.confirmation, for: firstKey, now: fixture.now)

    let loaded = try await store.loadRecord(for: different)
    XCTAssertNil(loaded.record)
}

func testCorruptRootMovesRecoveryCopyAndCreatesEmptyVersionOneDocument() async throws {
    let fixture = makeFixture()
    try Data("{not-json".utf8).write(to: fixture.fileURL)
    let store = FileHighlightClipReviewStore(
        fileURL: fixture.fileURL,
        now: { Date(timeIntervalSince1970: 1_700_000_000) },
    )

    let result = try await store.loadRecord(for: fixture.key)
    let files = try FileManager.default.contentsOfDirectory(
        at: fixture.fileURL.deletingLastPathComponent(),
        includingPropertiesForKeys: nil,
    )
    let document = try JSONDecoder().decode(
        HighlightClipReviewStoreDocument.self,
        from: Data(contentsOf: fixture.fileURL),
    )

    XCTAssertEqual(result.notice, .corruptDocumentRecovered)
    XCTAssertEqual(document, .empty)
    XCTAssertEqual(
        files.filter { $0.lastPathComponent.hasPrefix("highlight-clip-reviews.corrupt-") }.count,
        1,
    )
}

func testHigherSchemaLoadsWithoutRecordAndCannotBeOverwritten() async throws {
    let fixture = makeFixture()
    let futureBytes = Data(#"{"schemaVersion":2,"records":[{"future":true}]}"#.utf8)
    try futureBytes.write(to: fixture.fileURL)
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

    let result = try await store.loadRecord(for: fixture.key)
    XCTAssertNil(result.record)
    XCTAssertEqual(result.notice, .unsupportedSchemaVersion(2))
    await XCTAssertThrowsErrorAsync(
        try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now),
    ) {
        XCTAssertEqual($0 as? HighlightClipReviewStoreError, .unsupportedSchemaVersion(2))
    }
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), futureBytes)
}
~~~

- [ ] **Step 2: Write failing upsert, concurrency and lifecycle tests**

In the same file add:

~~~swift
func testUpsertRoundTripsAcrossStoreInstances() async throws {
    let fixture = makeFixture()
    try await FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        .upsert(fixture.confirmation, for: fixture.key, now: fixture.now)

    let loaded = try await FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        .loadRecord(for: fixture.key)

    XCTAssertEqual(loaded.record?.confirmedItems, [fixture.confirmation])
    XCTAssertEqual(loaded.record?.combination, fixture.key.combination)
}

func testSecondConfirmationReplacesIdentityAndPreservesOriginalDefaultBaseline() async throws {
    let fixture = makeFixture()
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
    try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
    let replacement = fixture.confirmation.replacing(
        defaultStart: 5,
        defaultDuration: 3,
        start: 12,
        duration: 3,
        isIncluded: false,
        confirmedAt: fixture.now.addingTimeInterval(10),
    )

    try await store.upsert(replacement, for: fixture.key, now: replacement.confirmedAt)
    let record = try await store.loadRecord(for: fixture.key).record!
    let items = record.confirmedItems

    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(record.createdAt, fixture.now)
    XCTAssertEqual(record.updatedAt, replacement.confirmedAt)
    XCTAssertEqual(items[0].defaultStart, fixture.confirmation.defaultStart)
    XCTAssertEqual(items[0].defaultDuration, fixture.confirmation.defaultDuration)
    XCTAssertEqual(items[0].start, 12)
    XCTAssertEqual(items[0].duration, 3)
    XCTAssertFalse(items[0].isIncluded)
}

func testAtomicWriterFailureLeavesPreviousBytesAndValueUntouched() async throws {
    let fixture = makeFixture()
    let working = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
    try await working.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
    let oldBytes = try Data(contentsOf: fixture.fileURL)
    let failing = FileHighlightClipReviewStore(
        fileURL: fixture.fileURL,
        atomicWrite: { _, _ in throw TestError.writeFailed },
    )

    await XCTAssertThrowsErrorAsync(
        try await failing.upsert(
            fixture.confirmation.replacing(start: 20),
            for: fixture.key,
            now: fixture.now.addingTimeInterval(1),
        ),
    )

    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), oldBytes)
    XCTAssertEqual(
        try await working.loadRecord(for: fixture.key).record?.confirmedItems[0].start,
        fixture.confirmation.start,
    )
}

func testConcurrentUpsertsRetainEverySuccessfulDistinctItem() async throws {
    let fixture = makeFixture()
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
    let confirmations = (1...8).map { fixture.confirmation.withMarker(index: $0) }

    try await withThrowingTaskGroup(of: Void.self) { group in
        for confirmation in confirmations {
            group.addTask {
                try await store.upsert(confirmation, for: fixture.key, now: confirmation.confirmedAt)
            }
        }
        try await group.waitForAll()
    }

    let loaded = try await store.loadRecord(for: fixture.key).record!.confirmedItems
    XCTAssertEqual(Set(loaded.map(\.identity)), Set(confirmations.map(\.identity)))
}

func testOverlappingDifferentConfirmationIdentityIsRejected() async throws {
    let fixture = makeFixture()
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
    try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
    let overlap = fixture.confirmation.withMarkerIDs([
        fixture.confirmation.markerIDs[0],
        storeMarkerID(2),
    ])

    await XCTAssertThrowsErrorAsync(
        try await store.upsert(overlap, for: fixture.key, now: fixture.now),
    ) {
        XCTAssertEqual($0 as? HighlightClipReviewStoreError, .duplicateMarkerAssignment)
    }
}

func testDeleteTrainingRemovesAllItsCombinationsOnly() async throws {
    let fixture = makeFixture()
    let other = makeFixture(trainingID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!)
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
    try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
    try await store.upsert(other.confirmation, for: other.key, now: other.now)

    try await store.deleteRecords(forTrainingSessionID: fixture.key.combination.training.id)

    let deleted = try await store.loadRecord(for: fixture.key)
    let preserved = try await store.loadRecord(for: other.key)
    XCTAssertNil(deleted.record)
    XCTAssertNotNil(preserved.record)
}

func testReconcileRemovesMissingAndChangedTrainingIdentities() async throws {
    let fixture = makeFixture()
    let current = makeFixture(trainingID: fixture.key.combination.training.id, markerOffset: 1)
    let retained = makeFixture(trainingID: UUID(uuidString: "00000000-0000-0000-0000-000000000088")!)
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
    try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
    try await store.upsert(retained.confirmation, for: retained.key, now: retained.now)

    try await store.reconcile(validTrainingIdentities: [
        current.key.combination.training,
        retained.key.combination.training,
    ])

    let removed = try await store.loadRecord(for: fixture.key)
    let preserved = try await store.loadRecord(for: retained.key)
    XCTAssertNil(removed.record)
    XCTAssertNotNil(preserved.record)
}

func testDifferentCombinationsForSameTrainingCoexist() async throws {
    let fixture = makeFixture()
    let otherOrder = fixture.reversingVideoOrder()
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

    try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
    try await store.upsert(otherOrder.confirmation, for: otherOrder.key, now: otherOrder.now)

    let originalLoaded = try await store.loadRecord(for: fixture.key)
    let reorderedLoaded = try await store.loadRecord(for: otherOrder.key)
    XCTAssertEqual(originalLoaded.record?.confirmedItems, [fixture.confirmation])
    XCTAssertEqual(reorderedLoaded.record?.confirmedItems, [otherOrder.confirmation])
}

func testExcludedConfirmationRoundTripsRangeAndState() async throws {
    let fixture = makeFixture()
    let excluded = fixture.confirmation.replacing(
        start: 4.2,
        duration: 3.1,
        isIncluded: false,
    )
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

    try await store.upsert(excluded, for: fixture.key, now: fixture.now)
    let loaded = try await store.loadRecord(for: fixture.key).record!.confirmedItems[0]

    XCTAssertEqual(loaded.start, 4.2)
    XCTAssertEqual(loaded.duration, 3.1)
    XCTAssertFalse(loaded.isIncluded)
}

func testLoadingDefaultsWithoutUpsertDoesNotCreateARecordOrFile() async throws {
    let fixture = makeFixture()
    let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

    _ = try await store.loadRecord(for: fixture.key)

    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
}
~~~

Define every Store-test fixture in the same file; do not reuse helpers from another test target:

~~~swift
private final class StoreFixture: @unchecked Sendable {
    let directoryURL: URL
    let fileURL: URL
    let key: HighlightClipReviewCombinationKey
    let confirmation: PersistedHighlightClipConfirmation
    let now: Date
    private let ownsDirectory: Bool

    init(
        directoryURL: URL,
        key: HighlightClipReviewCombinationKey,
        confirmation: PersistedHighlightClipConfirmation,
        now: Date,
        ownsDirectory: Bool = true,
    ) {
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent("highlight-clip-reviews.json")
        self.key = key
        self.confirmation = confirmation
        self.now = now
        self.ownsDirectory = ownsDirectory
    }

    deinit {
        if ownsDirectory {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func reversingVideoOrder() -> StoreFixture {
        let reversed = HighlightClipReviewCombination(
            training: key.combination.training,
            videos: Array(key.combination.videos.reversed()),
        )
        return StoreFixture(
            directoryURL: directoryURL,
            key: HighlightClipReviewCombinationKey(
                digest: "\(key.digest)-reversed",
                combination: reversed,
            ),
            confirmation: confirmation,
            now: now.addingTimeInterval(1),
            ownsDirectory: false,
        )
    }
}

private func makeFixture(
    trainingID: UUID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000100",
    )!,
    markerOffset: Int = 0,
) -> StoreFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
    )
    let markers = (1...8).map { index in
        HighlightClipReviewMarkerIdentity(
            id: storeMarkerID(markerOffset + index),
            markedAtMilliseconds: Int64(110_000 + ((markerOffset + index) * 1_000)),
        )
    }
    let training = HighlightClipReviewTrainingIdentity(
        id: trainingID,
        startedAtMilliseconds: 100_000,
        endedAtMilliseconds: 200_000,
        markers: markers,
    )
    let videos = [
        HighlightClipReviewVideoIdentity(
            source: .photoLibraryAsset("asset-a"),
            recordedStartAtMilliseconds: 100_000,
            durationTicks: 60 * 600,
        ),
        HighlightClipReviewVideoIdentity(
            source: .photoLibraryAsset("asset-b"),
            recordedStartAtMilliseconds: 200_000,
            durationTicks: 60 * 600,
        ),
    ]
    let combination = HighlightClipReviewCombination(
        training: training,
        videos: videos,
    )
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return StoreFixture(
        directoryURL: directory,
        key: HighlightClipReviewCombinationKey(
            digest: "digest-\(trainingID.uuidString)-\(markerOffset)",
            combination: combination,
        ),
        confirmation: PersistedHighlightClipConfirmation(
            videoIdentity: videos[0],
            markerIDs: [markers[0].id],
            defaultStart: 1,
            defaultDuration: 2,
            start: 1,
            duration: 2,
            isIncluded: true,
            confirmedAt: now,
        ),
        now: now,
    )
}

private func makeDifferentCombination(
    from value: HighlightClipReviewCombination,
) -> HighlightClipReviewCombination {
    HighlightClipReviewCombination(
        training: HighlightClipReviewTrainingIdentity(
            id: value.training.id,
            startedAtMilliseconds: value.training.startedAtMilliseconds + 1,
            endedAtMilliseconds: value.training.endedAtMilliseconds,
            markers: value.training.markers,
        ),
        videos: value.videos,
    )
}

private func storeMarkerID(_ index: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            90_000 + index,
        ),
    )!
}

private extension PersistedHighlightClipConfirmation {
    func replacing(
        defaultStart: TimeInterval? = nil,
        defaultDuration: TimeInterval? = nil,
        start: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        isIncluded: Bool? = nil,
        confirmedAt: Date? = nil,
    ) -> Self {
        Self(
            videoIdentity: videoIdentity,
            markerIDs: markerIDs,
            defaultStart: defaultStart ?? self.defaultStart,
            defaultDuration: defaultDuration ?? self.defaultDuration,
            start: start ?? self.start,
            duration: duration ?? self.duration,
            isIncluded: isIncluded ?? self.isIncluded,
            confirmedAt: confirmedAt ?? self.confirmedAt,
        )
    }

    func withMarker(index: Int) -> Self {
        withMarkerIDs([storeMarkerID(index)])
            .replacing(confirmedAt: confirmedAt.addingTimeInterval(Double(index)))
    }

    func withMarkerIDs(_ markerIDs: [UUID]) -> Self {
        Self(
            videoIdentity: videoIdentity,
            markerIDs: markerIDs,
            defaultStart: defaultStart,
            defaultDuration: defaultDuration,
            start: start,
            duration: duration,
            isIncluded: isIncluded,
            confirmedAt: confirmedAt,
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw")
    } catch {
        errorHandler(error)
    }
}

private enum TestError: Error {
    case writeFailed
}
~~~

- [ ] **Step 3: Run the Store suite and verify it fails**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewStoreTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: FAIL because the Store protocol and actor implementations do not exist.

- [ ] **Step 4: Define Store results and errors**

Create ShotMarker/Services/HighlightClipReviewStore.swift beginning with:

~~~swift
import Foundation

enum HighlightClipReviewStoreNotice: Equatable, Sendable {
    case corruptDocumentRecovered
    case unsupportedSchemaVersion(Int)
}

struct HighlightClipReviewStoreLoadResult: Equatable, Sendable {
    let record: PersistedHighlightClipReview?
    let notice: HighlightClipReviewStoreNotice?
}

enum HighlightClipReviewStoreError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidConfirmation
    case duplicateMarkerAssignment

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            "片段确认数据来自更新版本，请更新 App 后再确认。"
        case .invalidConfirmation:
            "片段确认数据无效，请恢复默认范围后再试。"
        case .duplicateMarkerAssignment:
            "片段关联打点冲突，请重新进入审核。"
        }
    }
}

protocol HighlightClipReviewStoring: Sendable {
    func loadRecord(
        for key: HighlightClipReviewCombinationKey,
    ) async throws -> HighlightClipReviewStoreLoadResult

    func upsert(
        _ confirmation: PersistedHighlightClipConfirmation,
        for key: HighlightClipReviewCombinationKey,
        now: Date,
    ) async throws

    func deleteRecords(forTrainingSessionID id: UUID) async throws

    func reconcile(
        validTrainingIdentities: Set<HighlightClipReviewTrainingIdentity>,
    ) async throws
}
~~~

- [ ] **Step 5: Implement decoding, corruption recovery and full-key matching**

Implement FileHighlightClipReviewStore as an actor. Its initializer is:

~~~swift
actor FileHighlightClipReviewStore: HighlightClipReviewStoring {
    typealias AtomicWrite = @Sendable (Data, URL) throws -> Void

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        atomicWrite: @escaping AtomicWrite = FileHighlightClipReviewStore.writeAtomically,
    )
}
~~~

The default URL is Application Support/ShotMarker/highlight-clip-reviews.json. loadDocument performs these ordered checks:

1. Missing file returns (.empty, nil) without creating a file.
2. Decode only a private SchemaHeader first.
3. schemaVersion > 1 returns the original bytes untouched and notice .unsupportedSchemaVersion(version).
4. schemaVersion < 1, or a version 1 full decode failure, moves the file to the UTC recovery name, writes HighlightClipReviewStoreDocument.empty, and returns .corruptDocumentRecovered. Version 1 is the first supported schema, so there is no lower-version migration.
5. loadRecord filters first by combinationDigest and then requires record.combination == key.combination.

Use JSONEncoder with prettyPrinted and sortedKeys. Recovery filenames use a POSIX UTC DateFormatter with yyyyMMdd'T'HHmmss'Z', and never appear in a user-facing error.

- [ ] **Step 6: Implement validated upsert and explicit same-directory atomic replacement**

Before mutation require non-empty unique markerIDs, membership of every marker in key.combination.training.markers, membership of the complete videoIdentity in key.combination.videos, a non-empty videoIdentity.source.value, normalized finite default/current ranges, and both ranges within the duration represented by videoIdentity.durationTicks / 600. A new record sets createdAt and updatedAt to now. An existing record preserves createdAt and updates updatedAt to now. For an existing confirmation identity, preserve its original defaultStart/defaultDuration while replacing start, duration, isIncluded and confirmedAt. Reject marker overlap with any different identity.

The default writer must:

~~~swift
private static func writeAtomically(_ data: Data, to fileURL: URL) throws {
    let fileManager = FileManager.default
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporaryURL = directory.appendingPathComponent(
        ".highlight-clip-reviews-\(UUID().uuidString).tmp",
    )
    do {
        try data.write(to: temporaryURL)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    } catch {
        try? fileManager.removeItem(at: temporaryURL)
        throw error
    }
}
~~~

Every actor upsert reloads the latest document inside the actor before merging, then performs one atomic replacement. Check Task cancellation before starting the write; after the write begins, finish the document update and return normally so callers can publish the matching in-memory state.

- [ ] **Step 7: Implement deletion, reconciliation and memory parity**

deleteRecords removes every record whose combination.training.id equals the requested ID. reconcile retains only records whose complete combination.training is present in validTrainingIdentities. Both skip writing when no record changes, reject an unsupported schema without overwriting it, and use the same atomic writer when they do change.

Implement InMemoryHighlightClipReviewStore as an actor conforming to the same protocol. Give tests initializer controls for seedDocument, loadError, upsertError, deleteError and reconcileError. Expose actor-isolated upsertCount, deletedTrainingSessionIDs, lastValidTrainingIdentities and confirmations(for:) for deterministic assertions. Its upsert must use the same replacement/baseline/overlap rules as the file actor, not a weaker dictionary shortcut.

- [ ] **Step 8: Run Store tests and inspect the persisted JSON**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewStoreTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS. In the round-trip test, additionally decode the written root and assert schemaVersion == 1, records.count == 1, and that no encoded key contains thumbnail, filmstrip, player, temporaryURL, errorMessage or displayNumber.

- [ ] **Step 9: Commit the Store**

~~~bash
git add \
  ShotMarker/Services/HighlightClipReviewStore.swift \
  ShotMarkerTests/HighlightClipReviewStoreTests.swift
git commit -m "feat: 持久化逐片段确认"
~~~

---

### Task 4: 以纯规划恢复已确认项并重建其余默认项

**Files:**

- Create: ShotMarker/Services/HighlightClipReviewRestoration.swift
- Create: ShotMarkerTests/HighlightClipReviewRestorationTests.swift
- Modify: ShotMarker/Services/HighlightClipReviewPlanner.swift:89-143,360-362
- Modify: ShotMarker/Models/HighlightClipReview.swift:17-69

**Interfaces:**

- Produces: HighlightClipReviewRestorationResult(draft:discardedConfirmationCount:)
- Produces: HighlightClipReviewPlanner.restoreDraft(for:videos:clipSettings:persistedRecord:)
- Changes: HighlightClipReviewPlanner.isNormalizedTenth 从 private 改为模块内可见，供同类型扩展验证持久范围。
- Guarantees: 合法确认项先占用打点；剩余默认项不会跨过已确认项合并；最终卡片按原始匹配编号稳定交错。
- Consumes: Task 1 的组合/确认模型和 Task 3 返回的 PersistedHighlightClipReview。

- [ ] **Step 1: Write failing restoration tests for absence, partial confirmation and exclusion**

Create ShotMarkerTests/HighlightClipReviewRestorationTests.swift. Use two videos with explicit reviewSourceIdentity and four chronologically ordered markers. Add:

~~~swift
func testNoRecordMatchesCurrentDefaultDraftExactly() {
    let fixture = makeFixture()

    let restored = HighlightClipReviewPlanner.restoreDraft(
        for: fixture.session,
        videos: fixture.videos,
        clipSettings: fixture.settings,
        persistedRecord: nil,
    )

    XCTAssertEqual(
        restored.draft,
        HighlightClipReviewPlanner.makeDraft(
            for: fixture.session,
            videos: fixture.videos,
            clipSettings: fixture.settings,
        ),
    )
    XCTAssertTrue(restored.draft.items.allSatisfy {
        $0.confirmationState == .defaultValue
    })
    XCTAssertEqual(restored.discardedConfirmationCount, 0)
}

func testConfirmedItemRestoresExactRangeBaselineMarkersAndIncludedState() {
    let fixture = makeFixture()
    let confirmation = makeConfirmation(
        fixture: fixture,
        markerIDs: [fixture.markers[1].id],
        defaultStart: 8,
        defaultDuration: 13,
        start: 10.2,
        duration: 2.4,
        isIncluded: true,
    )

    let restored = restore(fixture, confirmations: [confirmation])
    let item = restored.draft.items.first {
        $0.markerReferences.map(\.id) == confirmation.markerIDs
    }!

    XCTAssertEqual(item.defaultRange, HighlightClipRange(start: 8, duration: 13))
    XCTAssertEqual(item.range, HighlightClipRange(start: 10.2, duration: 2.4))
    XCTAssertTrue(item.isIncluded)
    XCTAssertEqual(item.confirmationState, .confirmed)
}

func testConfirmedExcludedMarkersNeverReturnAsDefaultItems() {
    let fixture = makeFixture()
    let markerIDs = [fixture.markers[1].id, fixture.markers[2].id]
    let confirmation = makeConfirmation(
        fixture: fixture,
        markerIDs: markerIDs,
        start: 10,
        duration: 4,
        isIncluded: false,
    )

    let restored = restore(fixture, confirmations: [confirmation])
    let occurrences = restored.draft.items
        .flatMap(\.markerReferences)
        .filter { markerIDs.contains($0.id) }

    XCTAssertEqual(occurrences.map(\.id), markerIDs)
    XCTAssertFalse(restored.draft.items.first {
        $0.markerReferences.map(\.id) == markerIDs
    }!.isIncluded)
}
~~~

- [ ] **Step 2: Add failing settings, ordering, invalid-item and summary tests**

Add the remaining semantic cases:

~~~swift
func testChangingGlobalDurationsReplansOnlyDefaultItems() {
    let fixture = makeFixture()
    let confirmation = makeConfirmation(
        fixture: fixture,
        markerIDs: [fixture.markers[1].id],
        defaultStart: 8,
        defaultDuration: 13,
        start: 10,
        duration: 2,
        isIncluded: true,
    )
    let original = restore(fixture, confirmations: [confirmation])
    var changedSettings = fixture.settings
    changedSettings.secondsBeforeMarker = 2
    changedSettings.secondsAfterMarker = 2

    let changed = HighlightClipReviewPlanner.restoreDraft(
        for: fixture.session,
        videos: fixture.videos,
        clipSettings: changedSettings,
        persistedRecord: record(fixture, confirmations: [confirmation]),
    )

    let originalConfirmed = original.draft.items.first { $0.confirmationState == .confirmed }
    let changedConfirmed = changed.draft.items.first { $0.confirmationState == .confirmed }
    XCTAssertEqual(changedConfirmed, originalConfirmed)
    XCTAssertNotEqual(
        changed.draft.items.filter { $0.confirmationState == .defaultValue }.map(\.range),
        original.draft.items.filter { $0.confirmationState == .defaultValue }.map(\.range),
    )
}

func testDefaultItemsDoNotMergeAcrossConfirmedMarkerAndOrderStaysOriginal() {
    let fixture = makeCloseMarkerFixture()
    let middle = makeConfirmation(
        fixture: fixture,
        markerIDs: [fixture.markers[1].id],
        start: 10,
        duration: 1,
        isIncluded: true,
    )

    let items = restore(fixture, confirmations: [middle]).draft.items

    XCTAssertEqual(items.count, 3)
    XCTAssertEqual(items.map { $0.markerReferences.map(\.id) }, [
        [fixture.markers[0].id],
        [fixture.markers[1].id],
        [fixture.markers[2].id],
    ])
    XCTAssertEqual(items.map(\.confirmationState), [
        .defaultValue, .confirmed, .defaultValue,
    ])
}

func testOneInvalidConfirmationFallsBackOnlyItsMarkersAndReportsCount() {
    let fixture = makeFixture()
    let valid = makeConfirmation(
        fixture: fixture,
        markerIDs: [fixture.markers[0].id],
        start: 2,
        duration: 2,
        isIncluded: true,
    )
    let invalid = makeConfirmation(
        fixture: fixture,
        markerIDs: [fixture.markers[2].id],
        start: -1,
        duration: 0,
        isIncluded: true,
    )

    let restored = restore(fixture, confirmations: [valid, invalid])

    XCTAssertEqual(restored.discardedConfirmationCount, 1)
    XCTAssertEqual(
        restored.draft.items.first {
            $0.markerReferences.contains { $0.id == valid.markerIDs[0] }
        }?.confirmationState,
        .confirmed,
    )
    XCTAssertEqual(
        restored.draft.items.first {
            $0.markerReferences.contains { $0.id == invalid.markerIDs[0] }
        }?.confirmationState,
        .defaultValue,
    )
}

func testRestoredDraftUsesExistingSummaryAndSnapshotPipeline() throws {
    let fixture = makeFixture()
    let excluded = makeConfirmation(
        fixture: fixture,
        markerIDs: [fixture.markers[1].id],
        start: 10,
        duration: 2,
        isIncluded: false,
    )
    let draft = restore(fixture, confirmations: [excluded]).draft

    let summary = try HighlightClipReviewPlanner.makeSummary(
        items: draft.items,
        videos: fixture.videos,
    )
    let segments = try HighlightClipReviewPlanner.validateConfirmedSegments(
        summary.finalSegments,
        videos: fixture.videos,
        validMarkerIDs: Set(draft.items.flatMap(\.markerReferences).map(\.id)),
    )

    XCTAssertEqual(summary.excludedMarkerCount, 1)
    XCTAssertFalse(segments.flatMap(\.markerIDs).contains(excluded.markerIDs[0]))
}
~~~

Add this table-driven invalid-item test:

~~~swift
func testEveryInvalidConfirmationFallsBackWithoutDiscardingLegalDefaults() {
    let fixture = makeFixture()
    let base = makeConfirmation(
        fixture: fixture,
        markerIDs: [fixture.markers[0].id],
        start: 2,
        duration: 2,
        isIncluded: true,
    )
    let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000009999")!
    let otherVideoIdentity = HighlightClipReviewVideoIdentity(
        source: .photoLibraryAsset("other"),
        recordedStartAtMilliseconds: 0,
        durationTicks: 600,
    )
    let invalidItems = [
        altered(base, markerIDs: [missingID]),
        altered(base, markerIDs: [fixture.markers[0].id, fixture.markers[0].id]),
        altered(base, markerIDs: [fixture.markers[1].id, fixture.markers[0].id]),
        altered(base, markerIDs: [fixture.markers[0].id, fixture.markers[2].id]),
        altered(base, markerIDs: [fixture.markers[2].id, fixture.markers[3].id]),
        altered(base, videoIdentity: otherVideoIdentity),
        altered(base, start: fixture.videos[0].duration, duration: 2),
        altered(base, defaultStart: -1, defaultDuration: 0),
        altered(base, start: 2.05, duration: 1.95),
    ]

    for invalid in invalidItems {
        let restored = restore(fixture, confirmations: [invalid])
        XCTAssertEqual(restored.discardedConfirmationCount, 1)
        XCTAssertTrue(restored.draft.items.allSatisfy {
            $0.confirmationState == .defaultValue
        })
        XCTAssertEqual(
            Set(restored.draft.items.flatMap(\.markerReferences).map(\.id)),
            Set(
                HighlightClipReviewPlanner.makeDraft(
                    for: fixture.session,
                    videos: fixture.videos,
                    clipSettings: fixture.settings,
                )
                .items
                .flatMap(\.markerReferences)
                .map(\.id),
            ),
        )
    }
}

private func altered(
    _ value: PersistedHighlightClipConfirmation,
    videoIdentity: HighlightClipReviewVideoIdentity? = nil,
    markerIDs: [UUID]? = nil,
    defaultStart: TimeInterval? = nil,
    defaultDuration: TimeInterval? = nil,
    start: TimeInterval? = nil,
    duration: TimeInterval? = nil,
) -> PersistedHighlightClipConfirmation {
    PersistedHighlightClipConfirmation(
        videoIdentity: videoIdentity ?? value.videoIdentity,
        markerIDs: markerIDs ?? value.markerIDs,
        defaultStart: defaultStart ?? value.defaultStart,
        defaultDuration: defaultDuration ?? value.defaultDuration,
        start: start ?? value.start,
        duration: duration ?? value.duration,
        isIncluded: value.isIncluded,
        confirmedAt: value.confirmedAt,
    )
}
~~~

Use these exact local fixtures so the two-video mapping, close-marker merge case, record key and persisted baseline are deterministic:

~~~swift
private struct RestorationFixture {
    let session: TrainingSession
    let videos: [SelectedTrainingVideo]
    let settings: ClipSettings

    var markers: [ShotMarkerEvent] { session.events }
}

private func makeFixture() -> RestorationFixture {
    let firstStart = Date(timeIntervalSince1970: 100)
    let secondStart = Date(timeIntervalSince1970: 200)
    let markers = [
        makeRestorationMarker(index: 1, at: 110),
        makeRestorationMarker(index: 2, at: 130),
        makeRestorationMarker(index: 3, at: 150),
        makeRestorationMarker(index: 4, at: 210),
    ]
    return RestorationFixture(
        session: TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000400")!,
            startedAt: firstStart,
            endedAt: secondStart.addingTimeInterval(80),
            events: markers,
        ),
        videos: [
            SelectedTrainingVideo(
                id: "runtime-a",
                recordedStartAt: firstStart,
                duration: 80,
                reviewSourceIdentity: .photoLibraryAsset("asset-a"),
            ),
            SelectedTrainingVideo(
                id: "runtime-b",
                recordedStartAt: secondStart,
                duration: 80,
                reviewSourceIdentity: .photoLibraryAsset("asset-b"),
            ),
        ],
        settings: .default,
    )
}

private func makeCloseMarkerFixture() -> RestorationFixture {
    let start = Date(timeIntervalSince1970: 100)
    return RestorationFixture(
        session: TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            events: [
                makeRestorationMarker(index: 11, at: 110),
                makeRestorationMarker(index: 12, at: 111),
                makeRestorationMarker(index: 13, at: 112),
            ],
        ),
        videos: [
            SelectedTrainingVideo(
                id: "runtime-close",
                recordedStartAt: start,
                duration: 60,
                reviewSourceIdentity: .photoLibraryAsset("asset-close"),
            ),
        ],
        settings: .default,
    )
}

private func makeRestorationMarker(
    index: Int,
    at timestamp: TimeInterval,
) -> ShotMarkerEvent {
    ShotMarkerEvent(
        id: UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                40_000 + index,
            ),
        )!,
        markedAt: Date(timeIntervalSince1970: timestamp),
    )
}

private func makeConfirmation(
    fixture: RestorationFixture,
    markerIDs: [UUID],
    defaultStart: TimeInterval = 1,
    defaultDuration: TimeInterval = 2,
    start: TimeInterval,
    duration: TimeInterval,
    isIncluded: Bool,
) -> PersistedHighlightClipConfirmation {
    let markerDates = markerIDs.compactMap { markerID in
        fixture.markers.first(where: { $0.id == markerID })?.markedAt
    }
    let video = fixture.videos.first { video in
        markerDates.allSatisfy {
            video.recordedStartAt <= $0 && $0 <= video.recordedEndAt
        }
    }!
    return PersistedHighlightClipConfirmation(
        videoIdentity: try! HighlightClipReviewIdentityBuilder.videoIdentity(for: video),
        markerIDs: markerIDs,
        defaultStart: defaultStart,
        defaultDuration: defaultDuration,
        start: start,
        duration: duration,
        isIncluded: isIncluded,
        confirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
    )
}

private func record(
    _ fixture: RestorationFixture,
    confirmations: [PersistedHighlightClipConfirmation],
) -> PersistedHighlightClipReview {
    let key = try! HighlightClipReviewIdentityBuilder.combinationKey(
        for: fixture.session,
        videos: fixture.videos,
    )
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return PersistedHighlightClipReview(
        combinationDigest: key.digest,
        combination: key.combination,
        confirmedItems: confirmations,
        createdAt: now,
        updatedAt: now,
    )
}

private func restore(
    _ fixture: RestorationFixture,
    confirmations: [PersistedHighlightClipConfirmation],
) -> HighlightClipReviewRestorationResult {
    HighlightClipReviewPlanner.restoreDraft(
        for: fixture.session,
        videos: fixture.videos,
        clipSettings: fixture.settings,
        persistedRecord: record(fixture, confirmations: confirmations),
    )
}
~~~

Each invalid item is evaluated in isolation, increments discardedConfirmationCount by one, creates no confirmed card, and leaves every currently matched marker available to default planning.

- [ ] **Step 3: Run the restoration suite and verify it fails**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewRestorationTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: FAIL because restoreDraft and restoration result do not exist.

- [ ] **Step 4: Define the restoration result and preserve confirmation state**

Add to ShotMarker/Models/HighlightClipReview.swift:

~~~swift
struct HighlightClipReviewRestorationResult: Equatable {
    let draft: HighlightClipReviewDraft
    let discardedConfirmationCount: Int
}
~~~

Ensure makeDraft assigns .defaultValue explicitly. Restored persisted items assign .confirmed. Do not infer state from a range comparison because confirming an unchanged default range must still produce .confirmed.

- [ ] **Step 5: Implement deterministic validation and marker occupation**

Create ShotMarker/Services/HighlightClipReviewRestoration.swift as an extension of HighlightClipReviewPlanner. The top-level signature is:

~~~swift
extension HighlightClipReviewPlanner {
    static func restoreDraft(
        for session: TrainingSession,
        videos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
        persistedRecord: PersistedHighlightClipReview?,
    ) -> HighlightClipReviewRestorationResult
}
~~~

Implement this exact flow:

1. Call makeDraft for the complete current session once and flatten markerReferences by originalMatchedNumber. This establishes current first-video matching, unmatched markers and stable display numbering.
2. Build dictionaries by marker UUID, runtime video ID and complete HighlightClipReviewVideoIdentity. A persisted confirmation is valid only when markerIDs are non-empty and unique; every marker still exists; all markers currently map to the complete video identity on the confirmation; their original numbers are ordered and contiguous; both current and default ranges pass validatedRange for that video's duration; all four stored time values are normalized tenths; and no accepted confirmation already occupies a marker.
3. Rebuild each legal confirmed item with id equal to markerIDs[0], the current runtime videoID, persisted default/current range and isIncluded, original marker references, and .confirmed.
4. Record every legal marker ID in occupiedMarkerIDs. Reject an invalid item as a whole, increment discardedConfirmationCount, and do not reserve any of its otherwise unclaimed markers.
5. Split flattened unoccupied marker references into contiguous runs separated by every occupied marker. For each run, create a temporary TrainingSession containing exactly those current events, call makeDraft with current settings, then rewrite each generated reference’s originalMatchedNumber from the complete-session map. This prevents default cards on opposite sides of a confirmed item from merging through it.
6. Concatenate confirmed and default cards and sort by the first originalMatchedNumber. Break a remaining tie by first marker UUID string, then by the current videos array index. Set selectedVideoCount to videos.count and totalMarkerCount to session.events.count.

Keep all I/O and user-facing strings outside this function. A corrupt item only changes discardedConfirmationCount.

- [ ] **Step 6: Run restoration plus existing planner regression tests**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewRestorationTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS. The no-record draft and every existing default planning expectation remain byte-for-value equivalent except for the new .defaultValue field.

- [ ] **Step 7: Commit pure restoration**

~~~bash
git add \
  ShotMarker/Models/HighlightClipReview.swift \
  ShotMarker/Services/HighlightClipReviewPlanner.swift \
  ShotMarker/Services/HighlightClipReviewRestoration.swift \
  ShotMarkerTests/HighlightClipReviewRestorationTests.swift \
  ShotMarkerTests/HighlightClipReviewPlannerTests.swift
git commit -m "feat: 恢复已确认与默认片段"
~~~

---

### Task 5: 把单片段编辑改为可放弃的工作副本

**Files:**

- Create: ShotMarker/ViewModels/HighlightClipEditorViewModel.swift
- Create: ShotMarkerTests/HighlightClipEditorViewModelTests.swift

**Interfaces:**

- Produces: HighlightClipConfirmationNavigation.open(itemID:) 和 .returnToReview。
- Produces: HighlightClipEditorViewModel.init(item:video:confirmWorkingCopy:)
- Produces: workingItem、displayedConfirmationState、hasChanges、isSaving、saveErrorMessage。
- Produces: apply(_:), adjustStart(by:), adjustEnd(by:), moveRange(by:), setIncluded(_:), restoreDefault(), discardChanges(), confirm()。
- Consumes: Task 4 的 HighlightClipReviewItem.confirmationState 与现有 HighlightClipReviewPlanner 范围约束。
- Guarantees: 本类型不引用 Store、JSON、SwiftUI View、AVPlayer 或共享审核 items。

- [ ] **Step 1: Write failing work-copy and status tests**

Create ShotMarkerTests/HighlightClipEditorViewModelTests.swift:

~~~swift
@MainActor
final class HighlightClipEditorViewModelTests: XCTestCase {
    func testOpeningDefaultAndConfirmedItemsCopiesEffectiveValues() {
        let defaultItem = makeItem(state: .defaultValue)
        let confirmedItem = makeItem(
            start: 12,
            duration: 3,
            included: false,
            state: .confirmed,
        )

        let defaultVM = makeViewModel(item: defaultItem)
        let confirmedVM = makeViewModel(item: confirmedItem)

        XCTAssertEqual(defaultVM.workingItem, defaultItem)
        XCTAssertEqual(defaultVM.displayedConfirmationState, .defaultValue)
        XCTAssertEqual(confirmedVM.workingItem, confirmedItem)
        XCTAssertEqual(confirmedVM.displayedConfirmationState, .confirmed)
        XCTAssertFalse(defaultVM.hasChanges)
        XCTAssertFalse(confirmedVM.hasChanges)
    }

    func testEveryEditChangesOnlyWorkingCopyAndConfirmedStateBecomesDefault() throws {
        let original = makeItem(state: .confirmed)
        let viewModel = makeViewModel(item: original)

        try viewModel.adjustStart(by: 0.5)
        viewModel.setIncluded(false)

        XCTAssertEqual(original.start, 10)
        XCTAssertTrue(original.isIncluded)
        XCTAssertNotEqual(viewModel.workingItem, original)
        XCTAssertTrue(viewModel.hasChanges)
        XCTAssertEqual(viewModel.displayedConfirmationState, .defaultValue)
    }

    func testRestoreDefaultChangesRangeOnly() throws {
        let viewModel = makeViewModel(
            item: makeItem(
                defaultStart: 8,
                defaultDuration: 5,
                start: 10,
                duration: 2,
                included: false,
                state: .confirmed,
            ),
        )

        viewModel.restoreDefault()

        XCTAssertEqual(viewModel.workingItem.range, HighlightClipRange(start: 8, duration: 5))
        XCTAssertFalse(viewModel.workingItem.isIncluded)
        XCTAssertTrue(viewModel.hasChanges)
        XCTAssertEqual(viewModel.displayedConfirmationState, .defaultValue)
    }

    func testChangingThenReturningToOpenedValuesStaysDirtyUntilConfirmOrDiscard() throws {
        let viewModel = makeViewModel(item: makeItem(state: .confirmed))

        try viewModel.moveRange(by: 1)
        try viewModel.moveRange(by: -1)

        XCTAssertEqual(viewModel.workingItem.range, HighlightClipRange(start: 10, duration: 2))
        XCTAssertTrue(viewModel.hasChanges)
        XCTAssertEqual(viewModel.displayedConfirmationState, .defaultValue)
    }

    func testDiscardRestoresOpenedValueAndClearsError() throws {
        let original = makeItem(state: .confirmed)
        let viewModel = makeViewModel(
            item: original,
            confirm: { _ in throw TestError.saveFailed },
        )
        try viewModel.moveRange(by: 1)
        _ = await viewModel.confirm()

        viewModel.discardChanges()

        XCTAssertEqual(viewModel.workingItem, original)
        XCTAssertEqual(viewModel.displayedConfirmationState, .confirmed)
        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertNil(viewModel.saveErrorMessage)
    }
}
~~~

- [ ] **Step 2: Write failing success, failure and duplicate-submit tests**

Add:

~~~swift
func testConfirmPassesWorkingCopyAndMarksItConfirmedOnSuccess() async throws {
    let recorder = ConfirmationRecorder(result: .success(.returnToReview))
    let viewModel = makeViewModel(item: makeItem(), confirm: recorder.confirm)
    try viewModel.adjustEnd(by: 0.5)

    let navigation = await viewModel.confirm()
    let submitted = await recorder.items()

    XCTAssertEqual(navigation, .returnToReview)
    XCTAssertEqual(submitted.count, 1)
    XCTAssertEqual(submitted[0].range, viewModel.workingItem.range)
    XCTAssertEqual(submitted[0].isIncluded, viewModel.workingItem.isIncluded)
    XCTAssertEqual(submitted[0].confirmationState, .defaultValue)
    XCTAssertEqual(viewModel.displayedConfirmationState, .confirmed)
    XCTAssertFalse(viewModel.hasChanges)
    XCTAssertNil(viewModel.saveErrorMessage)
}

func testFailedConfirmKeepsWorkingCopyDefaultStateAndAllowsRetry() async throws {
    let recorder = ConfirmationRecorder(result: .failure(TestError.saveFailed))
    let viewModel = makeViewModel(
        item: makeItem(state: .confirmed),
        confirm: recorder.confirm,
    )
    try viewModel.moveRange(by: 1)
    let edited = viewModel.workingItem

    let navigation = await viewModel.confirm()

    XCTAssertNil(navigation)
    XCTAssertEqual(viewModel.workingItem, edited)
    XCTAssertEqual(viewModel.displayedConfirmationState, .defaultValue)
    XCTAssertNotNil(viewModel.saveErrorMessage)
    XCTAssertFalse(viewModel.isSaving)
}

func testConcurrentButtonActionsInvokeConfirmationOnce() async {
    let gate = ConfirmationGate()
    let viewModel = makeViewModel(item: makeItem(), confirm: gate.confirm)

    async let first = viewModel.confirm()
    await gate.waitUntilEntered()
    async let second = viewModel.confirm()
    await Task.yield()
    await gate.release(with: .open(itemID: makeItem().id))
    _ = await (first, second)

    let callCount = await gate.callCount()
    XCTAssertEqual(callCount, 1)
}
~~~

Define the item factory, ViewModel factory and both actor recorders in this test file. The gate stores explicit entered/release continuations so the second call occurs while `isSaving` is true:

~~~swift
@MainActor
private func makeViewModel(
    item: HighlightClipReviewItem,
    confirm: @escaping HighlightClipEditorViewModel.ConfirmWorkingCopy = {
        _ in .returnToReview
    },
) -> HighlightClipEditorViewModel {
    HighlightClipEditorViewModel(
        item: item,
        video: SelectedTrainingVideo(
            id: item.videoID,
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
            reviewSourceIdentity: .photoLibraryAsset("editor-asset"),
        ),
        confirmWorkingCopy: confirm,
    )
}

private func makeItem(
    defaultStart: TimeInterval = 10,
    defaultDuration: TimeInterval = 2,
    start: TimeInterval = 10,
    duration: TimeInterval = 2,
    included: Bool = true,
    state: HighlightClipConfirmationState = .defaultValue,
) -> HighlightClipReviewItem {
    let markerID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000501",
    )!
    return HighlightClipReviewItem(
        id: markerID,
        videoID: "runtime-video",
        markerReferences: [
            HighlightClipMarkerReference(
                id: markerID,
                markedAt: Date(timeIntervalSince1970: 110),
                timeInVideo: 10,
                originalMatchedNumber: 1,
            ),
        ],
        defaultStart: defaultStart,
        defaultDuration: defaultDuration,
        start: start,
        duration: duration,
        isIncluded: included,
        confirmationState: state,
    )
}

private actor ConfirmationRecorder {
    private let result: Result<HighlightClipConfirmationNavigation, TestError>
    private var received: [HighlightClipReviewItem] = []

    init(result: Result<HighlightClipConfirmationNavigation, TestError>) {
        self.result = result
    }

    func confirm(
        _ item: HighlightClipReviewItem,
    ) async throws -> HighlightClipConfirmationNavigation {
        received.append(item)
        return try result.get()
    }

    func items() -> [HighlightClipReviewItem] {
        received
    }
}

private actor ConfirmationGate {
    private var entered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation:
        CheckedContinuation<HighlightClipConfirmationNavigation, Never>?
    private var invocations = 0

    func confirm(
        _: HighlightClipReviewItem,
    ) async throws -> HighlightClipConfirmationNavigation {
        invocations += 1
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func release(with result: HighlightClipConfirmationNavigation) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }

    func callCount() -> Int {
        invocations
    }
}

private enum TestError: LocalizedError, Equatable {
    case saveFailed

    var errorDescription: String? { "saveFailed" }
}
~~~

- [ ] **Step 3: Run the editor-state suite and verify it fails**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipEditorViewModelTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: FAIL because HighlightClipEditorViewModel and navigation result do not exist.

- [ ] **Step 4: Implement the editor ViewModel without shared mutation**

Create ShotMarker/ViewModels/HighlightClipEditorViewModel.swift:

~~~swift
import Combine
import Foundation

enum HighlightClipConfirmationNavigation: Equatable {
    case open(itemID: UUID)
    case returnToReview
}

@MainActor
final class HighlightClipEditorViewModel: ObservableObject {
    typealias ConfirmWorkingCopy =
        (HighlightClipReviewItem) async throws -> HighlightClipConfirmationNavigation

    @Published private(set) var workingItem: HighlightClipReviewItem
    @Published private(set) var hasChanges = false
    @Published private(set) var isSaving = false
    @Published private(set) var saveErrorMessage: String?

    let video: SelectedTrainingVideo
    private var openedItem: HighlightClipReviewItem
    private let confirmWorkingCopy: ConfirmWorkingCopy

    init(
        item: HighlightClipReviewItem,
        video: SelectedTrainingVideo,
        confirmWorkingCopy: @escaping ConfirmWorkingCopy,
    ) {
        openedItem = item
        workingItem = item
        self.video = video
        self.confirmWorkingCopy = confirmWorkingCopy
    }

    var displayedConfirmationState: HighlightClipConfirmationState {
        openedItem.confirmationState == .confirmed && !hasChanges
            ? .confirmed
            : .defaultValue
    }
}
~~~

Implement every range edit by passing workingItem and video.duration through HighlightClipReviewPlanner.apply, comparing the returned item with the prior working item, and setting hasChanges = true only for an effective difference. setIncluded and restoreDefault use the same effective-difference rule. Once true, hasChanges remains sticky even if later edits reproduce the opened values; this keeps the status “默认” after editing has begun. discardChanges restores openedItem, sets hasChanges = false and clears saveErrorMessage.

confirm guards !isSaving, sets isSaving before awaiting, and always resets it with defer. On success, set workingItem.confirmationState = .confirmed, copy it to openedItem, set hasChanges = false, clear the error and return the navigation. On error, retain every working value and hasChanges state, set the LocalizedError description or localizedDescription, and return nil. A second call while saving returns nil without invoking the closure.

- [ ] **Step 5: Run editor and range regression tests**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipEditorViewModelTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS. The original item supplied to the editor remains unchanged until the confirmation closure reports success.

- [ ] **Step 6: Commit the editor transaction**

~~~bash
git add \
  ShotMarker/ViewModels/HighlightClipEditorViewModel.swift \
  ShotMarkerTests/HighlightClipEditorViewModelTests.swift
git commit -m "feat: 隔离单片段编辑事务"
~~~

---

### Task 6: 在审核 ViewModel 中原子确认并决定连续导航

**Files:**

- Modify: ShotMarker/ViewModels/HighlightClipReviewViewModel.swift:13-189,248-341,502-512
- Modify: ShotMarkerTests/HighlightClipReviewViewModelTests.swift

**Interfaces:**

- Changes initializer: init(draft:videos:clipSettings:combinationKey:reviewStore:recoveryNoticeMessage:mediaProvider:now:submitSegments:onSubmissionSucceeded:)
- Produces: makeEditorViewModel(itemID:) -> HighlightClipEditorViewModel?
- Produces internally: confirmWorkingCopy(_:) async throws -> HighlightClipConfirmationNavigation。
- Preserves: confirmedSegments() 和 submit() 继续从当前生效 items 生成现有 ConfirmedHighlightSegment 快照。
- Consumes: Task 3 Store、Task 5 editor transaction 和 Task 1 stable video identity。

- [ ] **Step 1: Replace direct-mutation tests with failing transaction-boundary tests**

In ShotMarkerTests/HighlightClipReviewViewModelTests.swift remove expectations that setIncluded/apply/restoreDefault immediately mutate viewModel.items. Add:

~~~swift
@MainActor
func testEditorChangesDoNotTouchGalleryBeforeStoreSuccess() throws {
    let fixture = makeReviewViewModelFixture()
    let originalItems = fixture.viewModel.items
    let editor = fixture.viewModel.makeEditorViewModel(itemID: originalItems[0].id)!

    try editor.moveRange(by: 1)
    editor.setIncluded(false)

    XCTAssertNotEqual(editor.workingItem, originalItems[0])
    XCTAssertEqual(fixture.viewModel.items, originalItems)
    XCTAssertEqual(fixture.viewModel.summary, fixture.originalSummary)
}

@MainActor
func testDefaultItemCanBeConfirmedWithoutChangingRange() async {
    let fixture = makeReviewViewModelFixture()
    let editor = fixture.viewModel.makeEditorViewModel(itemID: fixture.viewModel.items[0].id)!

    let navigation = await editor.confirm()

    let upsertCount = await fixture.store.upsertCount
    XCTAssertNotNil(navigation)
    XCTAssertEqual(fixture.viewModel.items[0].confirmationState, .confirmed)
    XCTAssertEqual(upsertCount, 1)
}

@MainActor
func testStoreFailureKeepsGalleryAndNavigationUnchanged() async throws {
    let fixture = makeReviewViewModelFixture(storeError: TestError.writeFailed)
    let originalItems = fixture.viewModel.items
    let editor = fixture.viewModel.makeEditorViewModel(itemID: originalItems[0].id)!
    try editor.moveRange(by: 1)

    let navigation = await editor.confirm()

    XCTAssertNil(navigation)
    XCTAssertEqual(fixture.viewModel.items, originalItems)
    XCTAssertEqual(fixture.viewModel.editingItemID, originalItems[0].id)
    XCTAssertNotNil(editor.saveErrorMessage)
}
~~~

- [ ] **Step 2: Add failing normalization, source, replacement and navigation tests**

Add:

~~~swift
func testSuccessfulConfirmationNormalizesThenPersistsThenPublishes() async throws {
    let fixture = makeReviewViewModelFixture(now: Date(timeIntervalSince1970: 500))
    let firstID = fixture.viewModel.items[0].id
    let editor = fixture.viewModel.makeEditorViewModel(itemID: firstID)!
    try editor.apply(.replace(start: 10.06, duration: 2.04))

    _ = await editor.confirm()

    let persisted = await fixture.store.confirmations(for: fixture.key)
    XCTAssertEqual(persisted[0].start, 10.1)
    XCTAssertEqual(persisted[0].duration, 2.0)
    XCTAssertEqual(persisted[0].confirmedAt, Date(timeIntervalSince1970: 500))
    XCTAssertEqual(fixture.viewModel.items[0].range, HighlightClipRange(start: 10.1, duration: 2.0))
    XCTAssertEqual(fixture.viewModel.items[0].confirmationState, .confirmed)
}

func testIncludedUnavailableSourceCannotConfirmButExcludedCan() async {
    let fixture = makeReviewViewModelFixture(
        sourceError: .sourceUnavailable,
    )
    let itemID = fixture.viewModel.items[0].id
    fixture.viewModel.markSourceUnavailable(itemID: itemID)
    let included = fixture.viewModel.makeEditorViewModel(itemID: itemID)!

    let includedNavigation = await included.confirm()
    let beforeExclusionCount = await fixture.store.upsertCount
    XCTAssertNil(includedNavigation)
    XCTAssertEqual(beforeExclusionCount, 0)

    included.setIncluded(false)
    let excludedNavigation = await included.confirm()
    let afterExclusionCount = await fixture.store.upsertCount
    XCTAssertNotNil(excludedNavigation)
    XCTAssertEqual(afterExclusionCount, 1)
    XCTAssertFalse(fixture.viewModel.items[0].isIncluded)
}

func testConfirmationSkipsConfirmedCardsAndOpensFirstLaterDefault() async {
    let fixture = makeReviewViewModelFixture(states: [.defaultValue, .confirmed, .defaultValue])
    let editor = fixture.viewModel.makeEditorViewModel(itemID: fixture.viewModel.items[0].id)!
    let navigation = await editor.confirm()

    XCTAssertEqual(navigation, .open(itemID: fixture.viewModel.items[2].id))
}

func testConfirmationAfterLastLaterDefaultReturnsToReviewWithoutLooping() async {
    let fixture = makeReviewViewModelFixture(states: [.defaultValue, .confirmed, .confirmed])
    let editor = fixture.viewModel.makeEditorViewModel(itemID: fixture.viewModel.items[0].id)!

    let navigation = await editor.confirm()
    XCTAssertEqual(navigation, .returnToReview)
    XCTAssertNil(fixture.viewModel.editingItemID)
}

func testPageSubmissionAcceptsMixedConfirmedAndDefaultItems() async {
    let submitter = SegmentRecorder()
    let fixture = makeReviewViewModelFixture(
        states: [.confirmed, .defaultValue],
        submitSegments: submitter.submit,
    )

    XCTAssertTrue(fixture.viewModel.canConfirm)
    await fixture.viewModel.submit()
    let callCount = await submitter.callCount
    let lastMarkerIDs = await submitter.lastSegments.flatMap(\.markerIDs)

    XCTAssertEqual(callCount, 1)
    XCTAssertEqual(
        Set(lastMarkerIDs),
        Set(fixture.viewModel.items.filter(\.isIncluded).flatMap(\.markerReferences).map(\.id)),
    )
}
~~~

Keep these existing tests under their current names and make only the stated fixture/API changes:

- testThumbnailFailureShowsPlaceholderWithoutMarkingSourceUnavailable: construct the ViewModel with key/store; no editor transaction is needed.
- testEditedRangeRefreshesMidpointThumbnailWithoutClearingPreviousImage: confirm an edited editor working copy before asserting the gallery thumbnail refresh.
- testSubmitUsesCurrentSummarySegmentsAndPreservesDraftOnFailure and testDuplicateSubmitWhileSubmittingCallsClosureOnce: keep page-level submission assertions unchanged and inject the memory Store.
- testVideoIdentityDurationOrBeforeAfterChangeRequiresInvalidation, testMarkerLabelStyleOnlyChangeDoesNotRequireInvalidation and testFingerprintTreatsVideoOrderAsPlanningInput: give each video a stable source identity and retain the same expected booleans.
- testConfirmedSegmentsReturnsTheAlreadyDisplayedSummaryArray: use mixed .confirmed/.defaultValue items and assert the returned array equals summary.finalSegments.
- testFilmstripRefreshCancelsPreviousWindowRequest and testSubmitRevalidatesIncludedSourceWithoutTrustingCachedAsset: retain the existing media-provider gates.
- Move the range, inclusion, restore-default, half-second and playhead-working-copy assertions to HighlightClipEditorViewModelTests; delete the obsolete shared-items mutation versions after their replacements pass.

Add these self-contained fixtures below the test case. `makeReviewViewModelFixture` is only for the new Store-boundary tests, so the existing `makeViewModel` helper can continue returning a bare ViewModel for older tests:

~~~swift
@MainActor
private struct ReviewViewModelFixture {
    let viewModel: HighlightClipReviewViewModel
    let store: InMemoryHighlightClipReviewStore
    let key: HighlightClipReviewCombinationKey
    let originalSummary: HighlightClipReviewSummary
}

@MainActor
private func makeReviewViewModelFixture(
    states: [HighlightClipConfirmationState] = [
        .defaultValue,
        .defaultValue,
        .defaultValue,
    ],
    storeError: TestError? = nil,
    sourceError: HighlightClipReviewMediaError? = nil,
    now: Date = Date(timeIntervalSince1970: 400),
    recoveryNoticeMessage: String? = nil,
    submitSegments: @escaping HighlightClipReviewViewModel.SubmitSegments = { _ in },
) -> ReviewViewModelFixture {
    let video = SelectedTrainingVideo(
        id: "review-runtime-video",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
        reviewSourceIdentity: .photoLibraryAsset("review-asset"),
    )
    let events = states.indices.map { index in
        ShotMarkerEvent(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    60_100 + index,
                ),
            )!,
            markedAt: Date(timeIntervalSince1970: 110 + Double(index * 10)),
        )
    }
    let session = TrainingSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000600")!,
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 160),
        events: events,
    )
    let items = zip(events.indices, states).map { index, state in
        let event = events[index]
        return HighlightClipReviewItem(
            id: event.id,
            videoID: video.id,
            markerReferences: [
                HighlightClipMarkerReference(
                    id: event.id,
                    markedAt: event.markedAt,
                    timeInVideo: event.markedAt.timeIntervalSince(video.recordedStartAt),
                    originalMatchedNumber: index + 1,
                ),
            ],
            defaultStart: 10 + Double(index * 10),
            defaultDuration: 2,
            start: 10 + Double(index * 10),
            duration: 2,
            isIncluded: true,
            confirmationState: state,
        )
    }
    let key = try! HighlightClipReviewIdentityBuilder.combinationKey(
        for: session,
        videos: [video],
    )
    let store = InMemoryHighlightClipReviewStore(upsertError: storeError)
    let mediaProvider = HighlightClipReviewMediaProvider(
        cacheLimit: 8,
        loadAsset: { _ in
            if let sourceError {
                throw sourceError
            }
            return AVURLAsset(url: URL(fileURLWithPath: "/tmp/review-video.mov"))
        },
        generateFrame: { _, _ in Data([1]) },
    )
    let viewModel = HighlightClipReviewViewModel(
        draft: HighlightClipReviewDraft(
            selectedVideoCount: 1,
            totalMarkerCount: events.count,
            items: items,
        ),
        videos: [video],
        clipSettings: .default,
        combinationKey: key,
        reviewStore: store,
        recoveryNoticeMessage: recoveryNoticeMessage,
        mediaProvider: mediaProvider,
        now: { now },
        submitSegments: submitSegments,
    )
    return ReviewViewModelFixture(
        viewModel: viewModel,
        store: store,
        key: key,
        originalSummary: viewModel.summary,
    )
}

private actor SegmentRecorder {
    private(set) var callCount = 0
    private(set) var lastSegments: [ConfirmedHighlightSegment] = []

    func submit(_ segments: [ConfirmedHighlightSegment]) {
        callCount += 1
        lastSegments = segments
    }
}
~~~

Update the existing test helper's `makeVideo` to set `.photoLibraryAsset("legacy-test-asset-\(id)")`. After it has built `items`, create this exact key and pass it plus a fresh memory Store into the expanded initializer:

~~~swift
let session = TrainingSession(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000699")!,
    startedAt: video.recordedStartAt,
    endedAt: video.recordedEndAt,
    events: items.flatMap(\.markerReferences).map {
        ShotMarkerEvent(id: $0.id, markedAt: $0.markedAt)
    },
)
let key = try! HighlightClipReviewIdentityBuilder.combinationKey(
    for: session,
    videos: [video],
)

return HighlightClipReviewViewModel(
    draft: HighlightClipReviewDraft(
        selectedVideoCount: 1,
        totalMarkerCount: itemCount,
        items: items,
    ),
    videos: [video],
    clipSettings: .default,
    combinationKey: key,
    reviewStore: InMemoryHighlightClipReviewStore(),
    mediaProvider: mediaProvider,
    submitSegments: submitSegments,
)
~~~

Extend the file's existing private `TestError` with `case writeFailed`; keep its current `errorDescription` implementation so Store errors remain deterministic.

- [ ] **Step 3: Run the ViewModel suite and verify it fails**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: FAIL because the initializer, Store coordination and editor factory are not implemented.

- [ ] **Step 4: Inject the exact persistence dependencies**

Add properties:

~~~swift
@Published private(set) var recoveryNoticeMessage: String?

private let combinationKey: HighlightClipReviewCombinationKey
private let reviewStore: any HighlightClipReviewStoring
private let now: () -> Date
~~~

Extend init with combinationKey, reviewStore, recoveryNoticeMessage default nil, and now default Date.init. Remove originalItems and hasUserChanges: confirmed changes are durable, while unconfirmed changes live only in HighlightClipEditorViewModel and are guarded there.

- [ ] **Step 5: Build editor transactions from current effective cards**

Implement:

~~~swift
func makeEditorViewModel(itemID: UUID) -> HighlightClipEditorViewModel? {
    guard let item = items.first(where: { $0.id == itemID }),
          let video = videos.first(where: { $0.id == item.videoID })
    else {
        return nil
    }
    editingItemID = itemID
    return HighlightClipEditorViewModel(
        item: item,
        video: video,
        confirmWorkingCopy: { [weak self] workingItem in
            guard let self else {
                throw CancellationError()
            }
            return try await self.confirmWorkingCopy(workingItem)
        },
    )
}
~~~

closeEditor clears editingItemID only when the caller is returning to the gallery. Opening the next editor replaces it with the next ID.

- [ ] **Step 6: Implement write-before-publish confirmation**

confirmWorkingCopy follows this order:

1. Locate the current gallery item and require that ID, runtime videoID, marker references, and saved default baseline equal the editor’s immutable values.
2. Copy only start, duration and isIncluded from the working item.
3. Normalize start and end with normalizedTenths, derive normalized duration, and validate against the current video duration even for excluded cards.
4. If included, call mediaProvider.validateSourceAvailability for only that video. If excluded, skip the source-readability gate.
5. Call HighlightClipReviewIdentityBuilder.videoIdentity(for: video) and build PersistedHighlightClipConfirmation with that complete normalized video identity, the current item’s original default baseline, normalized range, current inclusion, and now().
6. Await reviewStore.upsert. Do not mutate any @Published property before it returns.
7. Set candidate.confirmationState = .confirmed, replace items[index], clear the card error/unavailable state when source validation succeeded, refresh the existing summary, and schedule that card’s thumbnail refresh.
8. Search items[(index + 1)...] for the first .defaultValue. Set editingItemID and return .open for a match; otherwise clear editingItemID and return .returnToReview.

Map identity, planning, source and Store failures through the existing userFacingMessage helper. Do not include identifiers or file paths in the message.

- [ ] **Step 7: Run ViewModel, Store, editor and job snapshot regressions**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests \
  -only-testing:ShotMarkerTests/HighlightClipEditorViewModelTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewStoreTests \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests \
  -only-testing:ShotMarkerTests/HighlightJobRunnerTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS. Store failure leaves items and summary unchanged; mixed confirmed/default cards still produce the same ConfirmedHighlightSegment task snapshot.

- [ ] **Step 8: Commit atomic ViewModel coordination**

~~~bash
git add \
  ShotMarker/ViewModels/HighlightClipReviewViewModel.swift \
  ShotMarkerTests/HighlightClipReviewViewModelTests.swift
git commit -m "feat: 原子确认并连续审核片段"
~~~

---

### Task 7: 在图集和编辑器呈现确认状态、固定保存入口与放弃提示

**Files:**

- Modify: ShotMarker/Views/HighlightClipEditorView.swift:4-475
- Modify: ShotMarker/Views/HighlightClipReviewView.swift:5-410

**Interfaces:**

- Changes: HighlightClipEditorView 接收 reviewViewModel、editorViewModel、playbackController 和 onConfirmationNavigation。
- Changes: HighlightClipEditorDestination 同时持有 HighlightClipEditorViewModel 与 HighlightClipPlaybackController。
- Consumes: Task 5 的工作副本和 Task 6 的 makeEditorViewModel。
- Produces UI behavior: gallery 状态、编辑器状态、DisclosureGroup、底部确认、可重试错误和确认后的 route replacement。

- [ ] **Step 1: Add explicit gallery status rendering before changing editor layout**

Replace stateLabel in HighlightClipReviewView with these four branches:

~~~swift
@ViewBuilder
private func stateLabel(
    item: HighlightClipReviewItem,
    unavailable: Bool,
) -> some View {
    if unavailable {
        Label("视频不可用", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
    } else {
        switch (item.confirmationState, item.isIncluded) {
        case (.defaultValue, _):
            Label("默认", systemImage: "circle.dashed")
                .foregroundStyle(.orange)
        case (.confirmed, true):
            Label("已确认 · 保留", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case (.confirmed, false):
            Label("已确认 · 排除", systemImage: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}
~~~

Keep the font at caption semibold and allow multiline text. Update cardAccessibilityLabel so it always includes one of “默认状态” or “已确认状态”, one of “保留” or “排除”, and, when unavailable, “视频不可用” after the saved/default status. Remove the separate duplicate “已排除” visual row because the combined confirmed status already communicates it; a default card remains initially included.

Display recoveryNoticeMessage above the grid as a non-blocking Label with exclamationmark.triangle and accessibility label. Do not use an alert that prevents direct generation.

- [ ] **Step 2: Change the destination to own one editor transaction**

Replace openEditor with:

~~~swift
private func openEditor(itemID: UUID) {
    guard let editorViewModel = viewModel.makeEditorViewModel(itemID: itemID) else {
        return
    }
    editorDestination = HighlightClipEditorDestination(
        id: itemID,
        editorViewModel: editorViewModel,
        playbackController: makePlaybackController(),
    )
}
~~~

The destination equality/hash remains based only on id. Pass both ViewModels into HighlightClipEditorView. Its confirmation callback first cancels the old item’s filmstrip and resets the old playback controller, then:

~~~swift
switch navigation {
case .open(let itemID):
    openEditor(itemID: itemID)
case .returnToReview:
    editorDestination = nil
    viewModel.closeEditor()
}
~~~

Changing to a later ID replaces the current destination and never pushes a second nested editor. A manual clean back sets destination nil and reloads the old gallery thumbnail through the existing onChange hook.

Replace the destination value type with this exact identity-only implementation:

~~~swift
private struct HighlightClipEditorDestination: Identifiable, Hashable {
    let id: UUID
    let editorViewModel: HighlightClipEditorViewModel
    let playbackController: HighlightClipPlaybackController

    static func == (
        lhs: HighlightClipEditorDestination,
        rhs: HighlightClipEditorDestination,
    ) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
~~~

- [ ] **Step 3: Rebind every editor control to workingItem**

Change HighlightClipEditorView stored inputs to:

~~~swift
@ObservedObject var reviewViewModel: HighlightClipReviewViewModel
@ObservedObject var editorViewModel: HighlightClipEditorViewModel
@ObservedObject var playbackController: HighlightClipPlaybackController

private let loadsMedia: Bool
private let onRequestVideoReselection: () -> Void
private let onConfirmationNavigation:
    (HighlightClipConfirmationNavigation) -> Void
~~~

item reads editorViewModel.workingItem and video reads editorViewModel.video. Timeline actions call editorViewModel.apply and then update/preview the playback controller exactly as the existing ViewModel method did. Toggle calls editorViewModel.setIncluded. Restore calls editorViewModel.restoreDefault. reviewViewModel remains responsible only for filmstrip requests, item source availability and media provider access.

- [ ] **Step 4: Make precise controls collapsed by default**

Add:

~~~swift
@State private var isFineTuningExpanded = false
~~~

Wrap only the three existing fineTuneGroup values in:

~~~swift
DisclosureGroup(
    "精确范围调整",
    isExpanded: $isFineTuningExpanded,
) {
    VStack(alignment: .leading, spacing: 14) {
        fineTuneGroup(
            title: "起点",
            negativeLabel: "-0.5s 更早",
            positiveLabel: "+0.5s 更晚",
            negativeDisabled: item.start <= 0,
            positiveDisabled: item.duration <= 1,
            negativeDisabledReason: "已到达视频起点",
            positiveDisabledReason: "片段已达到最短时长",
            negativeAction: .setStart(item.start - 0.5),
            positiveAction: .setStart(item.start + 0.5),
        )
        fineTuneGroup(
            title: "终点",
            negativeLabel: "-0.5s 更早",
            positiveLabel: "+0.5s 更晚",
            negativeDisabled: item.duration <= 1,
            positiveDisabled: item.range.end >= video.duration,
            negativeDisabledReason: "片段已达到最短时长",
            positiveDisabledReason: "已到达视频终点",
            negativeAction: .setEnd(item.range.end - 0.5),
            positiveAction: .setEnd(item.range.end + 0.5),
        )
        fineTuneGroup(
            title: "整体",
            negativeLabel: "-0.5s 向前",
            positiveLabel: "+0.5s 向后",
            negativeDisabled: item.start <= 0,
            positiveDisabled: item.range.end >= video.duration,
            negativeDisabledReason: "已到达视频起点",
            positiveDisabledReason: "已到达视频终点",
            negativeAction: .moveBy(-0.5),
            positiveAction: .moveBy(0.5),
        )
    }
    .padding(.top, 10)
}
.accessibilityValue(isFineTuningExpanded ? "已展开" : "已收起")
~~~

Move the DisclosureGroup into the scroll content. Keep playback preview, four time values, timeline, play button, inclusion toggle and restore-default button outside it. Because the State is initialized in each editor instance and never written elsewhere, leaving and reopening resets it to false.

- [ ] **Step 5: Add status, fixed confirmation action and retryable error**

At the top of the scroll content, show editorViewModel.displayedConfirmationState as “默认” with circle.dashed/orange or “已确认” with checkmark.circle.fill/green. Add a bottom safe-area inset:

~~~swift
.safeAreaInset(edge: .bottom) {
    VStack(spacing: 8) {
        if let message = editorViewModel.saveErrorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("保存失败，\(message)")
        }
        Button {
            confirmWorkingCopy()
        } label: {
            HStack {
                if editorViewModel.isSaving {
                    ProgressView()
                }
                Text(confirmButtonTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(editorViewModel.isSaving || cannotConfirmIncludedUnavailableSource)
    }
    .padding()
    .background(.regularMaterial)
}
~~~

confirmButtonTitle is “正在保存…” while saving, “排除并确认片段” when workingItem.isIncluded is false, and “确认片段” otherwise. confirmWorkingCopy pauses playback, awaits editorViewModel.confirm(), and calls onConfirmationNavigation only for a non-nil result.

Use these exact computed/action members; they keep the source gate on retained cards while allowing the shared transaction to confirm an exclusion:

~~~swift
private var cannotConfirmIncludedUnavailableSource: Bool {
    editorViewModel.workingItem.isIncluded
        && reviewViewModel.unavailableItemIDs.contains(editorViewModel.workingItem.id)
}

private var confirmButtonTitle: String {
    if editorViewModel.isSaving {
        return "正在保存…"
    }
    return editorViewModel.workingItem.isIncluded
        ? "确认片段"
        : "排除并确认片段"
}

private func confirmWorkingCopy() {
    playbackController.pause()
    Task { @MainActor in
        guard let navigation = await editorViewModel.confirm() else {
            return
        }
        onConfirmationNavigation(navigation)
    }
}
~~~

When the source is permanently unavailable, replace the old “排除此片段” action with “排除并确认片段”: setIncluded(false) and call the same confirmWorkingCopy function. “返回重新选择视频” first runs the dirty-exit flow; it cannot silently discard a changed working copy.

- [ ] **Step 6: Intercept dirty back navigation with the exact destructive choice**

Add isShowingDiscardConfirmation and pendingExitAction state. When hasChanges is false, the custom/standard back action dismisses immediately. When true, present:

~~~swift
.alert("放弃本次调整？", isPresented: $isShowingDiscardConfirmation) {
    Button("继续调整", role: .cancel) {
        pendingExitAction = nil
    }
    Button("放弃", role: .destructive) {
        editorViewModel.discardChanges()
        performPendingExit()
    }
} message: {
    Text("未确认的范围与保留状态更改不会保存。")
}
~~~

Always hide the system back button and provide a top-leading “返回” button with at least a 44-point hit area. Its action dismisses immediately when clean and shows the alert when dirty. pendingExitAction distinguishes returning to the gallery from returning to video selection. Do not call Store or delete a prior confirmation in either discard branch.

Define and route the two exit destinations explicitly:

~~~swift
private enum PendingEditorExitAction: Equatable {
    case review
    case videoSelection
}

@State private var isShowingDiscardConfirmation = false
@State private var pendingExitAction: PendingEditorExitAction?

private func requestExit(_ action: PendingEditorExitAction) {
    guard editorViewModel.hasChanges else {
        performExit(action)
        return
    }
    pendingExitAction = action
    isShowingDiscardConfirmation = true
}

private func performPendingExit() {
    guard let action = pendingExitAction else { return }
    pendingExitAction = nil
    performExit(action)
}

private func performExit(_ action: PendingEditorExitAction) {
    reviewViewModel.cancelFilmstripLoading(itemID: editorViewModel.workingItem.id)
    playbackController.reset()
    dismiss()
    if action == .videoSelection {
        onRequestVideoReselection()
    }
}
~~~

The toolbar button calls `requestExit(.review)`; “返回重新选择视频” calls `requestExit(.videoSelection)`.

- [ ] **Step 7: Build and exercise both previews**

Update HighlightClipReviewPreviewFixtures so the gallery includes one default retained card, one confirmed retained card, one confirmed excluded card and one unavailable confirmed card. The editor preview creates HighlightClipEditorViewModel with confirmWorkingCopy: { _ in .returnToReview } and an InMemoryHighlightClipReviewStore, so previews never write a real JSON file.

Run:

~~~bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: BUILD SUCCEEDED. Preview fixtures compile without writing a real JSON file.

- [ ] **Step 8: Commit the confirmation UI**

~~~bash
git add \
  ShotMarker/Views/HighlightClipEditorView.swift \
  ShotMarker/Views/HighlightClipReviewView.swift
git commit -m "feat: 展示片段确认与放弃状态"
~~~

---

### Task 8: 从训练和有序视频异步恢复审核组合

**Files:**

- Modify: ShotMarker/Views/TrainingSessionHighlightView.swift:8-194,235-309,376-393,827-1015
- Modify: ShotMarker/Views/HighlightClipReviewView.swift:15-25
- Modify: ShotMarker/ShotMarkerApp.swift:13-108
- Modify: ShotMarker/ContentView.swift:10-43
- Modify: ShotMarker/Views/TrainingSessionListView.swift:55-106,363-369
- Modify: ShotMarkerTests/HighlightClipReviewViewModelTests.swift

**Interfaces:**

- Changes: TrainingSessionHighlightView.init(session:highlightJobManager:reviewStore:)
- Produces: prepareReview() async，组合构建 → Store load → 恢复规划 → ViewModel。
- Preserves: 页面进入时停留图集，不自动打开第一个默认片段。
- Changes: 视频顺序或默认时长变化只丢弃当前图集实例；磁盘确认不删除。

- [ ] **Step 1: Add failing load/notice integration tests at the ViewModel boundary**

Add test fixture coverage to ShotMarkerTests/HighlightClipReviewViewModelTests.swift for the exact notice strings passed by the flow:

~~~swift
func testRecoveryNoticesAreNonBlockingAndDoNotDisableSubmission() {
    let corrupt = makeViewModel(recoveryNoticeMessage: "已恢复损坏的片段确认文件，当前使用默认范围。")
    let partial = makeViewModel(recoveryNoticeMessage: "部分已保存片段无法恢复，已使用默认范围。")
    let future = makeViewModel(
        recoveryNoticeMessage: "片段确认数据来自更新版本，当前使用默认范围；更新 App 后才能保存新的片段确认。",
    )

    XCTAssertTrue(corrupt.viewModel.canConfirm)
    XCTAssertTrue(partial.viewModel.canConfirm)
    XCTAssertTrue(future.viewModel.canConfirm)
    XCTAssertNotNil(corrupt.viewModel.recoveryNoticeMessage)
    XCTAssertNotNil(partial.viewModel.recoveryNoticeMessage)
    XCTAssertNotNil(future.viewModel.recoveryNoticeMessage)
}
~~~

The future-schema ViewModel still permits page-level generation from defaults; only per-item Store upsert fails with the actionable update message.

Extend the existing bare-ViewModel test helper with `recoveryNoticeMessage: String? = nil` and pass that value to the production initializer. No other fixture state changes for these three assertions.

- [ ] **Step 2: Inject Store and an explicit review-preparation state**

Add to TrainingSessionHighlightView:

~~~swift
private let reviewStore: any HighlightClipReviewStoring
@State private var isPreparingReview = false

init(
    session: TrainingSession,
    highlightJobManager: HighlightJobManager?,
    reviewStore: any HighlightClipReviewStoring,
) {
    self.session = session
    self.highlightJobManager = highlightJobManager
    self.reviewStore = reviewStore
}
~~~

In ShotMarkerApp.init construct one FileHighlightClipReviewStore, retain it on the App, and pass it through ContentView and TrainingSessionListView to TrainingSessionHighlightView. Give DEBUG previews InMemoryHighlightClipReviewStore(). The “下一步：审核片段” button starts Task { await prepareReview() }, displays “正在准备审核…” while active, and is disabled for duplicate preparation. This keeps Task 8 buildable without constructing a second live Store inside a View.

- [ ] **Step 3: Implement load and restoration before ViewModel creation**

Replace presentReview with @MainActor prepareReview() async:

~~~swift
@MainActor
private func prepareReview() async {
    guard !isPreparingReview else { return }
    isPreparingReview = true
    defer { isPreparingReview = false }

    let videos = selectedVideoItems.availableVideos
    let settings = clipSettings.normalized
    do {
        let key = try HighlightClipReviewIdentityBuilder.combinationKey(
            for: session,
            videos: videos,
        )
        let loaded = try await reviewStore.loadRecord(for: key)
        let restoration = HighlightClipReviewPlanner.restoreDraft(
            for: session,
            videos: videos,
            clipSettings: settings,
            persistedRecord: loaded.record,
        )
        installReviewViewModel(
            draft: restoration.draft,
            key: key,
            videos: videos,
            settings: settings,
            notice: reviewNotice(
                storeNotice: loaded.notice,
                discardedCount: restoration.discardedConfirmationCount,
            ),
        )
    } catch is CancellationError {
        return
    } catch {
        alert = HighlightFlowAlert(
            title: "无法准备片段审核",
            message: userFacingMessage(for: error),
        )
    }
}
~~~

installReviewViewModel contains the existing media provider, submitSegments and successful-job cleanup wiring, plus combinationKey, reviewStore and notice. It guards non-empty restored items and logs only counts and closed notice/error categories.

Use exact non-blocking notice copy:

- corruptDocumentRecovered → “已恢复损坏的片段确认文件，当前使用默认范围。”
- unsupportedSchemaVersion → “片段确认数据来自更新版本，当前使用默认范围；更新 App 后才能保存新的片段确认。”
- discardedConfirmationCount > 0 → “部分已保存片段无法恢复，已使用默认范围。”

When both a Store notice and discarded items exist, join the two sentences once. Do not include version integers, paths, IDs or digests.

- [ ] **Step 4: Preserve persisted confirmations across settings and selection changes**

Remove the old shouldGuardWholeFlowExit behavior and “放弃片段调整？” alert because confirmed changes are already durable and unconfirmed editor changes are guarded inside the editor.

Replace pendingReviewMutation’s destructive “更改视频或剪辑范围会丢失当前的排除与范围调整” path. Applying a video/order/default-duration mutation must:

1. Cancel review media loading.
2. Set reviewViewModel = nil and isReviewPresented = false.
3. Apply the mutation.
4. Keep reviewStore untouched.
5. On the next prepareReview, load the new exact combination. A default-duration-only change therefore recovers confirmed cards under the same key and replans only default cards.

MarkerLabelStyle remains outside requiresInvalidation and does not reconstruct the review. No successful Store confirmation should make the whole TrainingSessionHighlightView appear dirty.

- [ ] **Step 5: Prove identical and reordered inputs take the intended paths**

Add this integration test to HighlightClipReviewViewModelTests:

~~~swift
@MainActor
func testRecreatedReviewRestoresSameOrderAndReplansDefaultsForNewSettings() async throws {
    let fixture = makeReviewFlowFixture()
    let key = try HighlightClipReviewIdentityBuilder.combinationKey(
        for: fixture.session,
        videos: fixture.videos,
    )
    let first = fixture.makeViewModel(key: key)
    let editor = first.makeEditorViewModel(itemID: first.items[0].id)!
    try editor.moveRange(by: 1)
    _ = await editor.confirm()

    let loaded = try await fixture.store.loadRecord(for: key)
    var changedSettings = fixture.settings
    changedSettings.secondsBeforeMarker = 2
    changedSettings.secondsAfterMarker = 2
    let restored = HighlightClipReviewPlanner.restoreDraft(
        for: fixture.session,
        videos: fixture.videos,
        clipSettings: changedSettings,
        persistedRecord: loaded.record,
    )
    let recreated = fixture.makeViewModel(
        draft: restored.draft,
        key: key,
        settings: changedSettings,
    )

    XCTAssertNil(recreated.editingItemID)
    XCTAssertEqual(recreated.items[0].confirmationState, .confirmed)
    XCTAssertEqual(recreated.items[0].range, first.items[0].range)
    XCTAssertNotEqual(
        recreated.items.filter { $0.confirmationState == .defaultValue }.map(\.range),
        first.items.filter { $0.confirmationState == .defaultValue }.map(\.range),
    )
}

@MainActor
func testReversedVideoOrderDoesNotLoadOriginalCombinationRecord() async throws {
    let fixture = makeReviewFlowFixture()
    let originalKey = try HighlightClipReviewIdentityBuilder.combinationKey(
        for: fixture.session,
        videos: fixture.videos,
    )
    try await fixture.store.upsert(
        fixture.confirmation,
        for: originalKey,
        now: fixture.now,
    )
    let reversedKey = try HighlightClipReviewIdentityBuilder.combinationKey(
        for: fixture.session,
        videos: Array(fixture.videos.reversed()),
    )

    let reversedLoad = try await fixture.store.loadRecord(for: reversedKey)

    XCTAssertNil(reversedLoad.record)
}
~~~

Add this exact fixture in the same test file. Its first video covers two separated markers so confirming the first leaves a default card whose range visibly changes with new global settings; the second selected video makes order part of the combination even though it has no matched marker:

~~~swift
private struct ReviewFlowFixture {
    let session: TrainingSession
    let videos: [SelectedTrainingVideo]
    let settings: ClipSettings
    let store: InMemoryHighlightClipReviewStore
    let now: Date
    let confirmation: PersistedHighlightClipConfirmation

    @MainActor
    func makeViewModel(
        draft: HighlightClipReviewDraft? = nil,
        key: HighlightClipReviewCombinationKey,
        settings overrideSettings: ClipSettings? = nil,
    ) -> HighlightClipReviewViewModel {
        let effectiveSettings = overrideSettings ?? settings
        let effectiveDraft = draft ?? HighlightClipReviewPlanner.makeDraft(
            for: session,
            videos: videos,
            clipSettings: effectiveSettings,
        )
        return HighlightClipReviewViewModel(
            draft: effectiveDraft,
            videos: videos,
            clipSettings: effectiveSettings,
            combinationKey: key,
            reviewStore: store,
            mediaProvider: HighlightClipReviewMediaProvider(
                cacheLimit: 8,
                loadAsset: { _ in
                    AVURLAsset(url: URL(fileURLWithPath: "/tmp/review-flow.mov"))
                },
                generateFrame: { _, _ in Data([1]) },
            ),
            now: { now },
            submitSegments: { _ in },
        )
    }
}

private func makeReviewFlowFixture() -> ReviewFlowFixture {
    let firstStart = Date(timeIntervalSince1970: 100)
    let secondStart = Date(timeIntervalSince1970: 300)
    let firstMarker = ShotMarkerEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
        markedAt: Date(timeIntervalSince1970: 110),
    )
    let secondMarker = ShotMarkerEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
        markedAt: Date(timeIntervalSince1970: 140),
    )
    let firstSource = HighlightClipReviewSourceIdentity.photoLibraryAsset(
        "review-flow-asset-a",
    )
    let videos = [
        SelectedTrainingVideo(
            id: "review-flow-runtime-a",
            recordedStartAt: firstStart,
            duration: 60,
            reviewSourceIdentity: firstSource,
        ),
        SelectedTrainingVideo(
            id: "review-flow-runtime-b",
            recordedStartAt: secondStart,
            duration: 60,
            reviewSourceIdentity: .photoLibraryAsset("review-flow-asset-b"),
        ),
    ]
    let session = TrainingSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000800")!,
        startedAt: firstStart,
        endedAt: secondStart.addingTimeInterval(60),
        events: [firstMarker, secondMarker],
    )
    let now = Date(timeIntervalSince1970: 500)
    return ReviewFlowFixture(
        session: session,
        videos: videos,
        settings: .default,
        store: InMemoryHighlightClipReviewStore(),
        now: now,
        confirmation: PersistedHighlightClipConfirmation(
            videoIdentity: try! HighlightClipReviewIdentityBuilder.videoIdentity(
                for: videos[0],
            ),
            markerIDs: [firstMarker.id],
            defaultStart: 1,
            defaultDuration: 13,
            start: 1,
            duration: 13,
            isIncluded: true,
            confirmedAt: now,
        ),
    )
}
~~~

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewIdentityBuilderTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewRestorationTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS.

- [ ] **Step 6: Commit asynchronous review restoration**

~~~bash
git add \
  ShotMarker/Views/TrainingSessionHighlightView.swift \
  ShotMarker/Views/HighlightClipReviewView.swift \
  ShotMarker/ShotMarkerApp.swift \
  ShotMarker/ContentView.swift \
  ShotMarker/Views/TrainingSessionListView.swift \
  ShotMarkerTests/HighlightClipReviewViewModelTests.swift
git commit -m "feat: 恢复相同组合的片段确认"
~~~

---

### Task 9: 把 Store 接入训练删除、替换、合并和 Watch 导入生命周期

**Files:**

- Modify: ShotMarker/ShotMarkerApp.swift:13-108
- Modify: ShotMarker/ContentView.swift:10-43
- Modify: ShotMarker/Views/TrainingSessionListView.swift:55-178,236-296,363-430,559-604
- Modify: ShotMarker/ViewModels/TrainingSessionListViewModel.swift:42-240
- Modify: ShotMarker/Services/TrainingSessionImporter.swift:3-32
- Modify: ShotMarker/Services/TrainingSessionJSONTransferService.swift:23-78
- Modify: ShotMarker/Services/PhoneWatchSyncService.swift:34-71,112-207
- Modify: ShotMarkerTests/TrainingSessionImporterTests.swift
- Modify: ShotMarkerTests/TrainingSessionJSONTransferServiceTests.swift
- Modify: ShotMarkerTests/TrainingSessionListViewModelTests.swift
- Modify: ShotMarkerTests/PhoneWatchSyncServiceTests.swift

**Interfaces:**

- Changes: TrainingSessionImporting.import(_:) becomes async throws。
- Changes: TrainingSessionListViewModel.load(), importTrainingSessions(from:), mergeSelectedSessions() and deleteSelectedSessions() become async where Store cleanup is awaited.
- Changes: TrainingSessionJSONTransferService.importTrainingSessions becomes async throws。
- Produces: cleanup is best-effort after successful training persistence; only the next reconciliation retries failures.
- Preserves: Watch payload, ACK body, notification and four-event Analytics contract.

- [ ] **Step 1: Write failing replacement and reconciliation tests**

In TrainingSessionImporterTests add:

~~~swift
func testReplacingChangedWatchSessionDeletesItsReviewRecordsAfterTrainingSave() async throws {
    let original = makeSession(markerOffset: 0)
    let changed = makePayload(id: original.id, markerOffset: 1)
    let trainingStore = InMemoryTrainingSessionStore(sessions: [original])
    let reviewStore = InMemoryHighlightClipReviewStore()
    let importer = TrainingSessionImporter(
        store: trainingStore,
        reviewStore: reviewStore,
    )

    try await importer.import(changed)
    let deletedIDs = await reviewStore.deletedTrainingSessionIDs

    XCTAssertEqual(
        try trainingStore.loadTrainingSessions().first?.events.first?.id,
        changed.events.first?.id,
    )
    XCTAssertEqual(deletedIDs, [original.id])
}

func testImportingByteEquivalentTrainingDoesNotDeleteConfirmations() async throws {
    let session = makeSession()
    let reviewStore = InMemoryHighlightClipReviewStore()
    let importer = TrainingSessionImporter(
        store: InMemoryTrainingSessionStore(sessions: [session]),
        reviewStore: reviewStore,
    )

    try await importer.import(payload(from: session))
    let deletedIDs = await reviewStore.deletedTrainingSessionIDs

    XCTAssertTrue(deletedIDs.isEmpty)
}

func testCleanupFailureDoesNotFailSuccessfulTrainingImport() async throws {
    let original = makeSession(markerOffset: 0)
    let reviewStore = InMemoryHighlightClipReviewStore(deleteError: TestError.cleanupFailed)
    let importer = TrainingSessionImporter(
        store: InMemoryTrainingSessionStore(sessions: [original]),
        reviewStore: reviewStore,
    )

    try await importer.import(makePayload(id: original.id, markerOffset: 1))
}
~~~

Add these deterministic overloads inside `TrainingSessionImporterTests`, and the error at file scope. They coexist with the existing zero-argument `makePayload()` fixture:

~~~swift
private func makeSession(markerOffset: Int = 0) -> TrainingSession {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
    return TrainingSession(
        id: id,
        startedAt: Date(timeIntervalSince1970: 10_000),
        endedAt: Date(timeIntervalSince1970: 10_600),
        events: [
            ShotMarkerEvent(
                id: UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        702 + markerOffset,
                    ),
                )!,
                markedAt: Date(timeIntervalSince1970: 10_120 + Double(markerOffset)),
            ),
        ],
    )
}

private func makePayload(
    id: UUID,
    markerOffset: Int,
) -> TrainingSessionSyncPayload {
    let session = makeSession(markerOffset: markerOffset)
    return TrainingSessionSyncPayload(
        id: id,
        startedAt: session.startedAt,
        endedAt: session.endedAt,
        events: session.events.map {
            ShotMarkerEventSyncPayload(id: $0.id, markedAt: $0.markedAt)
        },
    )
}

private func payload(from session: TrainingSession) -> TrainingSessionSyncPayload {
    TrainingSessionSyncPayload(
        id: session.id,
        startedAt: session.startedAt,
        endedAt: session.endedAt,
        events: session.events.map {
            ShotMarkerEventSyncPayload(id: $0.id, markedAt: $0.markedAt)
        },
    )
}

private enum TestError: Error {
    case cleanupFailed
}
~~~

In TrainingSessionListViewModelTests add:

~~~swift
@MainActor
func testSuccessfulLoadReconcilesCompleteCurrentTrainingIdentities() async throws {
    let sessions = [
        try makeSession(id: "00000000-0000-0000-0000-000000000901"),
        try makeSession(id: "00000000-0000-0000-0000-000000000902"),
    ]
    let reviewStore = InMemoryHighlightClipReviewStore()
    let viewModel = TrainingSessionListViewModel(
        store: InMemoryTrainingSessionStore(sessions: sessions),
        reviewStore: reviewStore,
    )

    await viewModel.load()
    let reconciled = await reviewStore.lastValidTrainingIdentities

    XCTAssertEqual(
        reconciled,
        Set(sessions.map { HighlightClipReviewIdentityBuilder.trainingIdentity(for: $0) }),
    )
}

@MainActor
func testDeletingSelectionSavesTrainingFirstThenDeletesEverySelectedID() async throws {
    let first = try makeSession(id: "00000000-0000-0000-0000-000000000911")
    let second = try makeSession(id: "00000000-0000-0000-0000-000000000912")
    let trainingStore = InMemoryTrainingSessionStore(sessions: [first, second])
    let reviewStore = InMemoryHighlightClipReviewStore()
    let viewModel = TrainingSessionListViewModel(
        store: trainingStore,
        reviewStore: reviewStore,
    )
    await viewModel.load()
    viewModel.beginSelection(with: first.id)

    await viewModel.deleteSelectedSessions()
    let deletedIDs = await reviewStore.deletedTrainingSessionIDs

    XCTAssertEqual(try trainingStore.loadTrainingSessions(), [second])
    XCTAssertEqual(deletedIDs, [first.id])
}

@MainActor
func testMergeDeletesReviewRecordsForEverySelectedIDIncludingRetainedID() async throws {
    let first = try makeSession(
        id: "00000000-0000-0000-0000-000000000921",
        startedAt: Date(timeIntervalSince1970: 2_000),
    )
    let second = try makeSession(
        id: "00000000-0000-0000-0000-000000000922",
        startedAt: Date(timeIntervalSince1970: 3_000),
    )
    let reviewStore = InMemoryHighlightClipReviewStore()
    let viewModel = TrainingSessionListViewModel(
        store: InMemoryTrainingSessionStore(sessions: [first, second]),
        reviewStore: reviewStore,
    )
    await viewModel.load()
    viewModel.beginSelection(with: first.id)
    viewModel.toggleSelection(for: second.id)

    await viewModel.mergeSelectedSessions()
    let deletedIDs = await reviewStore.deletedTrainingSessionIDs

    XCTAssertEqual(
        Set(deletedIDs),
        Set([first.id, second.id]),
    )
    XCTAssertEqual(viewModel.rows.count, 1)
}
~~~

In TrainingSessionJSONTransferServiceTests add:

~~~swift
func testJSONImportDeletesOnlyReplacedChangedTrainingIdentities() async throws {
    let changedID = "00000000-0000-0000-0000-000000001301"
    let identicalID = "00000000-0000-0000-0000-000000001302"
    let insertedID = "00000000-0000-0000-0000-000000001303"
    let changedOriginal = try makeSession(id: changedID, startedAt: 1_000)
    let changedImport = try makeSession(id: changedID, startedAt: 1_100)
    let identical = try makeSession(id: identicalID, startedAt: 2_000)
    let inserted = try makeSession(id: insertedID, startedAt: 3_000)
    let reviewStore = InMemoryHighlightClipReviewStore()
    let service = TrainingSessionJSONTransferService(
        store: InMemoryTrainingSessionStore(sessions: [changedOriginal, identical]),
        reviewStore: reviewStore,
    )
    let bytes = try JSONEncoder().encode([changedImport, identical, inserted])

    let result = try await service.importTrainingSessions(from: bytes)
    let deletedIDs = await reviewStore.deletedTrainingSessionIDs

    XCTAssertEqual(result.importedCount, 3)
    XCTAssertEqual(result.replacedCount, 2)
    XCTAssertEqual(result.insertedCount, 1)
    XCTAssertEqual(deletedIDs, [changedOriginal.id])
}

func testJSONImportCleanupFailureStillReturnsSuccessfulImportResult() async throws {
    let changedID = "00000000-0000-0000-0000-000000001311"
    let original = try makeSession(id: changedID, startedAt: 1_000)
    let changed = try makeSession(id: changedID, startedAt: 1_100)
    let service = TrainingSessionJSONTransferService(
        store: InMemoryTrainingSessionStore(sessions: [original]),
        reviewStore: InMemoryHighlightClipReviewStore(
            deleteError: TestError.cleanupFailed,
        ),
    )

    let result = try await service.importTrainingSessions(
        from: JSONEncoder().encode([changed]),
    )

    XCTAssertEqual(result.replacedCount, 1)
}
~~~

Add `private enum TestError: Error { case cleanupFailed }` at file scope in `TrainingSessionJSONTransferServiceTests.swift`; it is intentionally file-local and does not depend on the identically named importer-test error.

- [ ] **Step 2: Write failing Watch ACK ordering test**

Change SpyTrainingSessionImporter to async and add a gate:

~~~swift
func testAckWaitsForTrainingImportAndReviewCleanupCompletion() async throws {
    let importer = GatedTrainingSessionImporter()
    let connectivity = FakePhoneWatchConnectivitySession(isSupported: true)
    let service = PhoneWatchSyncService(
        importer: importer,
        session: connectivity,
        analytics: SpyAnalyticsTracker(),
    )

    let userInfo = try makeCompletedTrainingSessionUserInfo(payload: makePayload())
    async let handling: Void = service.handleReceivedUserInfo(userInfo)
    await importer.waitUntilEntered()
    XCTAssertTrue(connectivity.transferredUserInfos.isEmpty)

    await importer.release()
    await handling

    XCTAssertEqual(connectivity.transferredUserInfos.count, 1)
    XCTAssertEqual(
        connectivity.transferredUserInfos[0][PhoneWatchSyncService.userInfoTypeKey] as? String,
        PhoneWatchSyncService.trainingSessionSyncAckUserInfoType,
    )
}
~~~

Add this gate at file scope in `PhoneWatchSyncServiceTests.swift`:

~~~swift
private actor GatedTrainingSessionImporter: TrainingSessionImporting {
    private var entered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func `import`(_: TrainingSessionSyncPayload) async throws {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
~~~

Retain existing decode, duplicate delivery, notification, error and Analytics assertions by awaiting handleReceivedUserInfo.

- [ ] **Step 3: Run lifecycle suites and verify they fail**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/TrainingSessionImporterTests \
  -only-testing:ShotMarkerTests/TrainingSessionJSONTransferServiceTests \
  -only-testing:ShotMarkerTests/TrainingSessionListViewModelTests \
  -only-testing:ShotMarkerTests/PhoneWatchSyncServiceTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: FAIL because the mutation APIs are synchronous and do not know the review Store.

- [ ] **Step 4: Make Watch and JSON replacement cleanup awaitable**

Change TrainingSessionImporting:

~~~swift
protocol TrainingSessionImporting {
    func `import`(_ payload: TrainingSessionSyncPayload) async throws
}
~~~

TrainingSessionImporter captures the previous session before replacing it, saves training-sessions.json first, then compares HighlightClipReviewIdentityBuilder.trainingIdentity. If the identity changed, await deleteRecords for that ID. Catch cleanup errors, log event highlight.review.cleanup.failed with errorCategory and affectedTrainingCount only, and return success so ACK is not withheld for a secondary-store failure.

Make PhoneWatchSyncService.handleReceivedUserInfo async. The WCSession delegate method starts one Task that awaits it. Keep payload decode, Analytics success, notification and ACK in the same order, with ACK after importer completion.

Make both TrainingSessionJSONTransferService import overloads async. Before saving, collect exact IDs whose previous training identity differs from the imported identity. After save succeeds, await deletion for those IDs; catch/log cleanup failures without changing TrainingSessionJSONImportResult.

- [ ] **Step 5: Reconcile on load and clean merge/delete mutations**

Inject reviewStore into TrainingSessionListViewModel. Make load async and, after a successful training load, await:

~~~swift
try await reviewStore.reconcile(
    validTrainingIdentities: Set(
        sessions.map { HighlightClipReviewIdentityBuilder.trainingIdentity(for: $0) },
    ),
)
~~~

If reconciliation fails, keep rows and clear the user-facing training error because training loading succeeded; log only errorCategory and trainingSessionCount.

Because `load()` is now async, update the existing notification observer body to `Task { @MainActor [weak self] in await self?.load() }`; this preserves notification-driven refresh without starting detached Store work.

For merge, save the new training list first, update rows/selection, post the existing notification, then await deleteRecords for every selected ID. For deleteSelectedSessions, require a nonempty selected set, save the retained list first, update rows/selection, post notification, then delete every removed ID. A cleanup failure does not restore deleted/merged training rows and is retried by the next load reconciliation.

- [ ] **Step 6: Restore the existing documented delete action in the list UI**

Show the bottom action bar whenever viewModel.isSelectionMode. It contains:

- A destructive “删除” button, enabled for one or more selected sessions, which presents “删除训练记录？” and lists the selected count.
- The existing “合并” button, enabled only when canMergeSelectedSessions.

The destructive confirmation starts Task { await viewModel.deleteSelectedSessions() }. The merge button starts Task { await viewModel.mergeSelectedSessions() }. Change the list .task to await viewModel.load(), and change the import completion handler to async so it awaits viewModel.importTrainingSessions.

- [ ] **Step 7: Reuse the single live Store in every training mutation owner**

Use the FileHighlightClipReviewStore already created and routed to TrainingSessionListView in Task 8. Pass that same instance into TrainingSessionImporter and TrainingSessionListViewModel. Every preview/test initializer continues to receive an explicit InMemoryHighlightClipReviewStore. Do not construct another live file Store inside a service, View or ViewModel.

- [ ] **Step 8: Run lifecycle and task-retention regressions**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/TrainingSessionImporterTests \
  -only-testing:ShotMarkerTests/TrainingSessionJSONTransferServiceTests \
  -only-testing:ShotMarkerTests/TrainingSessionListViewModelTests \
  -only-testing:ShotMarkerTests/PhoneWatchSyncServiceTests \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests \
  -only-testing:ShotMarkerTests/HighlightJobStoreTests \
  -only-testing:ShotMarkerTests/HighlightJobRunnerTests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS. Existing HighlightJob clear/cancel/restart tests require no review Store and therefore prove task lifecycle cannot delete confirmation records through hidden coupling.

- [ ] **Step 9: Commit lifecycle integration**

~~~bash
git add \
  ShotMarker/ShotMarkerApp.swift \
  ShotMarker/ContentView.swift \
  ShotMarker/Views/TrainingSessionListView.swift \
  ShotMarker/ViewModels/TrainingSessionListViewModel.swift \
  ShotMarker/Services/TrainingSessionImporter.swift \
  ShotMarker/Services/TrainingSessionJSONTransferService.swift \
  ShotMarker/Services/PhoneWatchSyncService.swift \
  ShotMarkerTests/TrainingSessionImporterTests.swift \
  ShotMarkerTests/TrainingSessionJSONTransferServiceTests.swift \
  ShotMarkerTests/TrainingSessionListViewModelTests.swift \
  ShotMarkerTests/PhoneWatchSyncServiceTests.swift
git commit -m "feat: 清理失效的片段确认记录"
~~~

---

### Task 10: 增加端到端 UI 回归并完成全量验证、文档与归档

**Files:**

- Create: ShotMarker/Views/HighlightClipConfirmationUITestHarnessView.swift
- Create: ShotMarkerUITests/HighlightClipConfirmationUITests.swift
- Modify: ShotMarker/ShotMarkerApp.swift:87-99
- Modify: docs/README.md
- Modify: docs/current/product.md
- Modify: docs/current/architecture.md
- Modify: docs/current/quality.md
- Modify: docs/current/status.md
- Create then archive: docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-validation.md
- Move after current docs are updated:
  - docs/changes/2026-09-03-highlight-clip-confirmation-spec.md
  - docs/changes/2026-09-03-highlight-clip-confirmation-plan.md

**Interfaces:**

- Produces: DEBUG-only SHOTMARKER_UI_TEST_CLIP_CONFIRMATION entry.
- Verifies: visible/accessibility status, transaction discard, consecutive navigation, direct default generation, Dynamic Type and Release exclusion.
- Requires at completion: superpowers:verification-before-completion, then superpowers:requesting-code-review, then superpowers:finishing-a-development-branch.

- [ ] **Step 1: Write failing XCUITest flows**

Create ShotMarkerUITests/HighlightClipConfirmationUITests.swift. Launch with SHOTMARKER_UI_TEST_CLIP_CONFIRMATION=1 and assert:

~~~swift
final class HighlightClipConfirmationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 5))
    }

    func testGalleryExposesAllFourStatesAndDefaultDoesNotDisableGeneration() {
        XCTAssertTrue(app.staticTexts["默认"].exists)
        XCTAssertTrue(app.staticTexts["已确认 · 保留"].exists)
        XCTAssertTrue(app.staticTexts["已确认 · 排除"].exists)
        XCTAssertTrue(app.staticTexts["视频不可用"].exists)
        XCTAssertTrue(app.buttons["确认并生成"].isEnabled)
    }

    func testPreciseControlsStartCollapsedAndResetAfterReentry() {
        app.buttons["片段 1"].tap()
        XCTAssertTrue(app.buttons["精确范围调整"].exists)
        XCTAssertFalse(app.buttons["-0.5s 更早"].exists)
        app.buttons["精确范围调整"].tap()
        XCTAssertTrue(app.buttons["-0.5s 更早"].waitForExistence(timeout: 2))
        app.buttons["返回"].tap()
        XCTAssertFalse(app.alerts["放弃本次调整？"].exists)
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 2))
        app.buttons["片段 1"].tap()
        XCTAssertFalse(app.buttons["-0.5s 更早"].exists)
    }

    func testDirtyBackCanContinueOrDiscardWithoutChangingGallery() {
        app.buttons["片段 2"].tap()
        app.switches["保留此片段"].tap()
        XCTAssertTrue(app.staticTexts["默认"].exists)
        app.buttons["返回"].tap()
        XCTAssertTrue(app.alerts["放弃本次调整？"].exists)
        app.alerts.buttons["继续调整"].tap()
        XCTAssertTrue(app.navigationBars.matching(
            NSPredicate(format: "identifier BEGINSWITH '片段'")
        ).firstMatch.exists)
        app.buttons["返回"].tap()
        app.alerts.buttons["放弃"].tap()
        XCTAssertTrue(app.staticTexts["已确认 · 保留"].waitForExistence(timeout: 2))
    }

    func testConfirmationSkipsConfirmedCardThenReturnsAfterLastDefault() {
        app.buttons["片段 1"].tap()
        app.buttons["确认片段"].tap()
        XCTAssertTrue(app.navigationBars["片段 3"].waitForExistence(timeout: 2))
        app.buttons["确认片段"].tap()
        XCTAssertTrue(app.navigationBars["审核集锦片段"].waitForExistence(timeout: 2))
    }
}
~~~

Add a separate launch with -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge. Assert the confirm button exists, is hittable, has frame.height >= 44, and the status labels have nonempty accessibility values.

- [ ] **Step 2: Build the deterministic DEBUG harness**

Create HighlightClipConfirmationUITestHarnessView under #if DEBUG. It builds five cards in order:

1. default retained;
2. confirmed retained;
3. default retained;
4. confirmed excluded;
5. confirmed excluded and marked unavailable for the source-error assertion.

Use explicit UUIDs, one SelectedTrainingVideo with .photoLibraryAsset("ui-test-asset"), an InMemoryHighlightClipReviewStore, loadsMedia: false, and a submit closure that sets an accessibility-visible “任务已创建” string. Mark card 5 unavailable after constructing the review ViewModel. Because cards 4 and 5 are excluded, the page-level generation action remains enabled. Card 2 lets the discard test return to “已确认 · 保留”; card 1 confirmation skips card 2 and opens card 3, and confirming card 3 skips cards 4–5 before returning to the gallery.

Extend ShotMarkerApp’s DEBUG routing:

~~~swift
if ProcessInfo.processInfo.environment["SHOTMARKER_UI_TEST_TIMELINE"] == "1" {
    HighlightClipTimelineUITestHarnessView()
} else if ProcessInfo.processInfo.environment[
    "SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"
] == "1" {
    HighlightClipConfirmationUITestHarnessView()
} else {
    contentView
}
~~~

- [ ] **Step 3: Run focused model, Store, flow and UI tests**

Run:

~~~bash
xcodebuild test \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ShotMarkerTests/HighlightClipReviewIdentityBuilderTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewContentHasherTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewStoreTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewRestorationTests \
  -only-testing:ShotMarkerTests/HighlightClipEditorViewModelTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewPlannerTests \
  -only-testing:ShotMarkerTests/HighlightClipReviewViewModelTests \
  -only-testing:ShotMarkerTests/TrainingVideoLoadingServiceTests \
  -only-testing:ShotMarkerTests/TrainingSessionImporterTests \
  -only-testing:ShotMarkerTests/TrainingSessionJSONTransferServiceTests \
  -only-testing:ShotMarkerTests/TrainingSessionListViewModelTests \
  -only-testing:ShotMarkerTests/PhoneWatchSyncServiceTests \
  -only-testing:ShotMarkerTests/HighlightJobManagerTests \
  -only-testing:ShotMarkerTests/HighlightJobRunnerTests \
  -only-testing:ShotMarkerUITests/HighlightClipConfirmationUITests \
  CODE_SIGNING_ALLOWED=NO
~~~

Expected: PASS with 0 failures and 0 skipped tests. Record the actual executed count from the result, not an estimate.

Commit the verified DEBUG harness and UI regression separately:

~~~bash
git add \
  ShotMarker/Views/HighlightClipConfirmationUITestHarnessView.swift \
  ShotMarker/ShotMarkerApp.swift \
  ShotMarkerUITests/HighlightClipConfirmationUITests.swift
git commit -m "test: 增加片段确认界面回归"
~~~

- [ ] **Step 4: Run the complete iPhone and Watch suites**

Run:

~~~bash
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
~~~

Expected: both schemes PASS with 0 failures and 0 skipped tests. Record exact counts and result-bundle locations. The Watch count demonstrates that TrainingSession and sync payload contracts remain compatible.

- [ ] **Step 5: Build Release and prove DEBUG harnesses are absent**

Run:

~~~bash
xcodebuild build \
  -project ShotMarker.xcodeproj \
  -scheme ShotMarker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ShotMarker-ClipConfirmation-Release \
  CODE_SIGNING_ALLOWED=NO

test -d /tmp/ShotMarker-ClipConfirmation-Release/Build/Products/Release-iphonesimulator/ShotMarker.app
test -d /tmp/ShotMarker-ClipConfirmation-Release/Build/Products/Release-iphonesimulator/ShotMarker.app.dSYM
test -f /tmp/ShotMarker-ClipConfirmation-Release/Build/Products/Release-iphonesimulator/ShotMarker.app/PrivacyInfo.xcprivacy

if strings /tmp/ShotMarker-ClipConfirmation-Release/Build/Products/Release-iphonesimulator/ShotMarker.app/ShotMarker \
  | rg 'SHOTMARKER_UI_TEST_(TIMELINE|CLIP_CONFIRMATION)'; then
  exit 1
fi
~~~

Expected: BUILD SUCCEEDED, App/dSYM/privacy manifest exist, and strings returns no DEBUG harness environment name.

- [ ] **Step 6: Perform the specified Simulator acceptance matrix**

Use at least one training containing both an ordinary and a merged card, plus two videos that can be selected in either order. Record the actual Simulator model and OS in the public validation file; route any optional physical-device evidence through the private documentation boundary above. Complete all of these observations:

1. First entry shows every card as “默认” and permits immediate “确认并生成”.
2. Confirming an adjusted first card shows “已确认 · 保留” and opens the next later default card.
3. Confirming an earlier card skips a confirmed middle card.
4. Confirming the last later default returns to the gallery without looping.
5. Terminating and relaunching the App with the same training and video order restores confirmed range/state.
6. A partially confirmed combination restores confirmed cards while remaining cards stay default and direct generation remains enabled.
7. Changing global before/after duration preserves confirmed cards and recalculates only default cards.
8. Reversing the same videos does not restore the original-order record.
9. Editing a confirmed card changes editor state to “默认”; choosing “放弃” restores the prior confirmed value.
10. Reconfirming an edited confirmed card replaces the old value rather than adding a duplicate.
11. “排除并确认片段” survives restart and its markers never return as defaults.
12. Injected Store write failure leaves the editor, working copy, gallery and navigation unchanged and permits retry.
13. “精确范围调整” starts collapsed, expands with all six 0.5-second controls, and starts collapsed after reentry.
14. Replacing/deleting/merging training content removes obsolete confirmation records without rolling back the training mutation.
15. Clearing a generated HighlightJob leaves the matching confirmation record available.
16. At maximum Dynamic Type, status text wraps and the discard dialog/bottom confirmation action remain readable and hittable.

Do not mark VoiceOver, physical device, TestFlight, App Store Connect, Analytics production or GlitchTip production as passed unless separately executed in this task.

- [ ] **Step 7: Run static privacy and diff checks**

Run:

~~~bash
git diff --check

rg -n \
  'reviewSourceIdentity|combinationDigest|fileSHA256|photoLibraryAsset' \
  ShotMarker/Services/AppLogging \
  ShotMarker/Services/Analytics \
  ShotMarker/Views \
  ShotMarker/ViewModels

plutil -lint ShotMarker/PrivacyInfo.xcprivacy
~~~

Expected: git diff --check and plutil pass. Inspect every rg match: Views/ViewModels may pass identity values internally but no logger, Analytics event, user-facing Text or error string may interpolate a raw identity, UUID, digest or file URL.

- [ ] **Step 8: Create the evidence-backed validation record**

Create docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-validation.md containing:

- implementation commit SHA and branch;
- Xcode/Swift versions;
- focused, full iPhone and full Watch commands with actual counts/results;
- Release command and artifact checks;
- Simulator model, OS version, media fixture properties and results for each of the 16 acceptance items;
- explicit “未执行” entries for VoiceOver, physical device, TestFlight and external services;
- remaining warnings or unrelated baseline failures without rewriting them as feature failures.

Every result must come from this execution. Do not copy the 2026-09-03 pre-change counts as if they validated the new code.

- [ ] **Step 9: Update current facts before archiving the Change**

Update:

- docs/current/product.md with implemented default/confirmed semantics, transaction behavior, continuous navigation and same-combination reuse.
- docs/current/architecture.md with stable source identity, full combination, Store path/schema, actor/atomic write, restoration flow and training cleanup boundary.
- docs/current/quality.md with the new dated focused/full/build evidence and precise untested scope.
- docs/current/status.md by removing this feature from “已确认但未实现” and summarizing the verified implementation.
- docs/README.md by moving the active Change link to the archive/history context.

Run:

~~~bash
wc -l \
  docs/current/product.md \
  docs/current/architecture.md \
  docs/current/quality.md \
  docs/current/status.md
~~~

Expected: every individual current document is at or below 300 lines.

- [ ] **Step 10: Archive spec and plan only after current docs are correct**

Run:

~~~bash
git mv \
  docs/changes/2026-09-03-highlight-clip-confirmation-spec.md \
  docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-spec.md

git mv \
  docs/changes/2026-09-03-highlight-clip-confirmation-plan.md \
  docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-plan.md
~~~

Then fix every repository link to the new archive locations and rerun:

~~~bash
rg -n '2026-09-03-highlight-clip-confirmation-(spec|plan)' docs
git diff --check
git status --short
~~~

Expected: references resolve to docs/archive/2026-09, diff check passes, and status contains only intended implementation/test/documentation changes.

- [ ] **Step 11: Commit evidence and governance updates**

~~~bash
git add \
  docs/README.md \
  docs/current/product.md \
  docs/current/architecture.md \
  docs/current/quality.md \
  docs/current/status.md \
  docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-validation.md \
  docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-spec.md \
  docs/archive/2026-09/2026-09-03-highlight-clip-confirmation-plan.md
git commit -m "docs: 记录并归档片段确认变更"
~~~

- [ ] **Step 12: Run the completion gate against the committed tree**

Invoke superpowers:verification-before-completion and rerun the full iPhone suite, full Watch suite, Release build and git diff --check against the final commit. Invoke superpowers:requesting-code-review and resolve every confirmed issue with a focused test. Then invoke superpowers:finishing-a-development-branch to present merge/PR/keep/discard options without choosing one on the user’s behalf.

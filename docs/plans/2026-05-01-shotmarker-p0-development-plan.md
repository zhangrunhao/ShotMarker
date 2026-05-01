# ShotMarker P0 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the first usable ShotMarker flow: record shot markers on Apple Watch, sync a training session to iPhone, select that training session and a compatible iPhone video, generate a highlight video, and save it to Photos.

**Architecture:** Keep P0 centered on training sessions, not a video library. Use a small shared domain layer for training sessions, marker events, clip settings, and clip planning; keep UI state in SwiftUI view models; keep AVFoundation export and Photos saving behind service types that can be tested independently.

**Tech Stack:** SwiftUI, Foundation, AVFoundation, PhotosUI, Photos, WatchKit, WatchConnectivity, XCTest.

## Product Plan Assessment

Your proposed plan is directionally sound:

1. 首页展示训练记录列表。
2. 手表支持记录开始、结束、打点并形成训练记录。
3. 选择训练记录并选择视频。
4. 跑通视频剪辑功能。
5. 根据训练记录剪辑视频。

The main adjustment is dependency order. Before UI and Watch work gets large, the app needs a small shared data model and testable clip-planning logic. Also, "跑通视频剪辑功能" and "根据训练记录剪辑视频" overlap; the healthier split is:

- First prove AVFoundation can export a simple known clip.
- Then feed it clip ranges computed from a training session and the selected video's start time.

The first version should not add a video list page. The iPhone home screen should be the training session list.

## Recommended Milestones

### Milestone 0: Project Foundation

Purpose: add test harness and shared domain types before feature UI.

**Files:**
- Create: `ShotMarker/Models/TrainingSession.swift`
- Create: `ShotMarker/Models/ShotMarkerEvent.swift`
- Create: `ShotMarker/Models/ClipSettings.swift`
- Create: `ShotMarker/Models/HighlightStatus.swift`
- Create: `ShotMarker/Services/TrainingSessionStore.swift`
- Create: `ShotMarkerTests/TrainingSessionStoreTests.swift`
- Modify: `ShotMarker.xcodeproj/project.pbxproj`

**Implementation notes:**
- Add an iOS unit test target named `ShotMarkerTests`.
- Keep models in the iOS app target first. When adding the Watch target, move shared files into target membership for both iOS and Watch if needed.
- Persist training sessions as JSON in Application Support for P0.

**Core types:**

```swift
struct ShotMarkerEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let markedAt: Date
    let source: String
}

struct TrainingSession: Identifiable, Codable, Equatable {
    let id: UUID
    var trainingDate: Date
    var startedAt: Date
    var endedAt: Date?
    var events: [ShotMarkerEvent]
    var syncStatus: SyncStatus
    var highlightStatus: HighlightStatus
}
```

**Verification:**
- Run: `xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17'`
- Expected: tests pass.

**Commit:**

```bash
git add ShotMarker ShotMarkerTests ShotMarker.xcodeproj
git commit -m "feat: 添加训练记录基础模型"
```

### Milestone 1: iPhone Home Training Session List

Purpose: build the first visible iPhone experience using local sample or stored training sessions.

**Files:**
- Create: `ShotMarker/ViewModels/TrainingSessionListViewModel.swift`
- Create: `ShotMarker/Views/TrainingSessionListView.swift`
- Create: `ShotMarker/Views/TrainingSessionRow.swift`
- Modify: `ShotMarker/ContentView.swift`
- Test: `ShotMarkerTests/TrainingSessionListViewModelTests.swift`

**Behavior:**
- Home displays training sessions.
- Each row shows date, time, marker count, highlight status, and sync status.
- Empty state is restrained and operational: no synced training sessions yet.
- No video list page.

**Testing:**
- View model sorts sessions newest first.
- Row display data maps correctly from `TrainingSession`.
- Empty state appears when store has no training sessions.

**Verification:**
- Run unit tests.
- Build app with `xcodebuild -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

**Commit:**

```bash
git add ShotMarker ShotMarkerTests
git commit -m "feat: 添加训练记录首页"
```

### Milestone 2: Watch Recording Flow

Purpose: let Apple Watch create a real training session.

**Files:**
- Modify: `ShotMarker.xcodeproj/project.pbxproj`
- Create: `ShotMarkerWatchApp/ShotMarkerWatchApp.swift`
- Create: `ShotMarkerWatchApp/Views/WatchTrainingView.swift`
- Create: `ShotMarkerWatchApp/ViewModels/WatchTrainingViewModel.swift`
- Create: `ShotMarkerWatchApp/Services/WatchTrainingSessionStore.swift`
- Test: `ShotMarkerTests/WatchTrainingSessionTests.swift`

**Behavior:**
- Watch app has one primary button.
- Long press starts training if idle.
- Double tap records a marker only while training.
- Successful marker records current absolute time and triggers haptic feedback.
- Long press ends training if active.
- Ending training writes one training session.

**Implementation notes:**
- Use a `TrainingSession` model to make start, mark, and end behavior testable without Watch UI.
- UI should be minimal: large button, current state, marker count.
- Haptic feedback stays in the Watch view layer, not the model.

**Verification:**
- Unit tests cover invalid states, such as double tap before training starts.
- Build both iOS and Watch targets.

**Commit:**

```bash
git add ShotMarker ShotMarkerWatchApp ShotMarkerTests ShotMarker.xcodeproj
git commit -m "feat: 添加手表训练打点流程"
```

### Milestone 3: Watch-to-iPhone Training Session Sync

Purpose: move completed training sessions from Watch to iPhone after training ends.

**Files:**
- Create: `ShotMarker/Services/PhoneWatchSyncService.swift`
- Create: `ShotMarkerWatchApp/Services/WatchSyncService.swift`
- Modify: `ShotMarker/Services/TrainingSessionStore.swift`
- Modify: `ShotMarker/ViewModels/TrainingSessionListViewModel.swift`
- Test: `ShotMarkerTests/TrainingSessionSyncImportTests.swift`

**Behavior:**
- Watch queues completed training sessions after long-press end.
- iPhone receives training sessions and saves them in local store.
- If sync fails or phone is unavailable, Watch keeps the session as pending sync.
- iPhone home refreshes after import.

**Implementation notes:**
- Prefer `WCSession.transferUserInfo` for completed training sessions.
- Do not require real-time sync for P0.
- Make import idempotent by training session `id`.

**Verification:**
- Unit test importing the same training session twice creates one local record.
- Manual test with paired Watch simulator or device if available.
- Build succeeds if Watch simulator is unavailable.

**Commit:**

```bash
git add ShotMarker ShotMarkerWatchApp ShotMarkerTests
git commit -m "feat: 同步手表训练记录"
```

### Milestone 4: Select Training Session and Choose Video

Purpose: connect the home list to Photos video selection.

**Files:**
- Create: `ShotMarker/ViewModels/HighlightCreationViewModel.swift`
- Create: `ShotMarker/Views/HighlightCreationView.swift`
- Create: `ShotMarker/Services/VideoSelectionService.swift`
- Create: `ShotMarker/Services/VideoMetadataReader.swift`
- Modify: `ShotMarker/Views/TrainingSessionListView.swift`
- Test: `ShotMarkerTests/VideoMetadataReaderTests.swift`

**Behavior:**
- Tapping a training session opens a creation screen or sheet.
- User chooses one video from Photos.
- P0 accepts only Apple-recorded standard videos with a usable recorded start time.
- If the selected video lacks a start time, show an error and keep the user on video selection.

**Implementation notes:**
- Use `PhotosPicker` or `PHPickerViewController`.
- Read `PHAsset.creationDate` and/or AV metadata as the recorded start-time source.
- Keep selected video temporary; do not build a local video list.

**Verification:**
- Unit test metadata validation with injectable test metadata.
- Manual test selecting a video from Photos.
- Confirm missing metadata blocks generation.

**Commit:**

```bash
git add ShotMarker ShotMarkerTests
git commit -m "feat: 添加训练记录视频选择流程"
```

### Milestone 5: Clip Planning From Training Session

Purpose: convert marker dates into video-relative clip ranges.

**Files:**
- Create: `ShotMarker/Services/ClipPlanner.swift`
- Create: `ShotMarker/Models/ClipRange.swift`
- Test: `ShotMarkerTests/ClipPlannerTests.swift`

**Behavior:**
- Given video start time, duration, training session, and clip settings, return ordered clip ranges.
- Default clip range is marker - 10 seconds through marker + 3 seconds.
- Clamp clips to video bounds.
- Ignore markers outside video duration.
- Do not merge overlapping clips.

**Key tests:**
- Marker at 30 seconds creates 20...33.
- Marker at 5 seconds creates 0...8.
- Marker after video end is ignored.
- Overlapping markers create two separate ranges.

**Verification:**
- Run `ClipPlannerTests`.
- Run full unit test suite.

**Commit:**

```bash
git add ShotMarker ShotMarkerTests
git commit -m "feat: 添加训练记录剪辑规划"
```

### Milestone 6: Basic Video Export Proof

Purpose: prove AVFoundation export works before integrating all marker timing logic.

**Files:**
- Create: `ShotMarker/Services/HighlightExporter.swift`
- Create: `ShotMarker/Services/TemporaryFileProvider.swift`
- Test: `ShotMarkerTests/HighlightExporterTests.swift`

**Behavior:**
- Given a local video asset and one known clip range, export a new `.mov` or `.mp4`.
- Preserve source audio.
- Write output to a temporary file.

**Implementation notes:**
- Use `AVMutableComposition`.
- Add both video and audio tracks when present.
- Keep this service independent from Photos saving.

**Verification:**
- Unit or integration test with a small fixture video if one is added.
- If fixture is too heavy for Git, document manual verification in the test plan and keep automated tests focused on composition input validation.
- Manual run exports a playable file.

**Commit:**

```bash
git add ShotMarker ShotMarkerTests
git commit -m "feat: 跑通基础视频剪辑导出"
```

### Milestone 7: Training-Session-Driven Highlight Generation

Purpose: combine selected training session, selected video, clip planner, exporter, and Photos saving.

**Files:**
- Create: `ShotMarker/Services/PhotoLibrarySaver.swift`
- Modify: `ShotMarker/ViewModels/HighlightCreationViewModel.swift`
- Modify: `ShotMarker/Views/HighlightCreationView.swift`
- Modify: `ShotMarker/Services/TrainingSessionStore.swift`
- Test: `ShotMarkerTests/HighlightCreationViewModelTests.swift`

**Behavior:**
- User selects training session.
- User selects valid video.
- App computes clip ranges from video start time and training session.
- App exports a highlight video.
- App saves highlight to Photos.
- App marks training session as clipped after save succeeds.
- App shows clear error if no markers fall inside video range.

**Verification:**
- Unit test successful state transition.
- Unit test no valid markers.
- Manual test with a real Photos video and sample training session.
- Run iOS build.

**Commit:**

```bash
git add ShotMarker ShotMarkerTests
git commit -m "feat: 根据训练记录生成集锦视频"
```

### Milestone 8: P0 Polish and Release Check

Purpose: make the first version coherent enough to use during real training.

**Files:**
- Modify: `ShotMarker/Views/TrainingSessionListView.swift`
- Modify: `ShotMarker/Views/HighlightCreationView.swift`
- Modify: `ShotMarkerWatchApp/Views/WatchTrainingView.swift`
- Modify: app `Info.plist` generated settings through Xcode build settings if permission strings are needed.
- Update: `docs/PRD.md` if behavior changes.

**Behavior:**
- Permission prompts are understandable.
- Empty, loading, generating, success, and error states exist.
- UI stays restrained and operational.
- No video list page appears.

**Verification:**
- Fresh iPhone simulator build.
- Fresh Watch simulator build if available.
- Manual end-to-end checklist:
  - Start Watch training.
  - Record at least three markers.
  - End training.
  - Confirm training session appears on iPhone.
  - Select training session.
  - Select valid video.
  - Generate highlight.
  - Confirm video is saved to Photos.

**Commit:**

```bash
git add ShotMarker ShotMarkerWatchApp ShotMarkerTests docs
git commit -m "chore: 完成 P0 验收检查"
```

## Suggested Execution Order

1. Milestone 0: foundation and tests.
2. Milestone 1: iPhone home with training session list using local/sample data.
3. Milestone 5: clip planning pure logic.
4. Milestone 6: basic video export proof.
5. Milestone 4: training session selection and video selection.
6. Milestone 7: training-session-driven generation and Photos saving.
7. Milestone 2: Watch recording.
8. Milestone 3: Watch-to-iPhone sync.
9. Milestone 8: polish and P0 acceptance.

This order gets the risky video math and export path proven early, while still preserving the product direction. If you want the Watch experience visible first, swap Milestones 2 and 5, but do not postpone ClipPlanner past video export integration.

## Risks

- Watch target setup may take longer than expected because the current project only has one iOS app target.
- Photos video start-time metadata can vary; P0 must fail clearly when metadata is missing.
- AVFoundation export with audio needs careful track handling.
- Simulator Photos testing can be awkward; at least one real-device test is likely needed before trusting the full flow.
- Training session sync should be idempotent so retries do not duplicate records.

## P0 Acceptance Criteria

- iPhone home shows training sessions, not a video list.
- Watch can start training, record markers, end training, and form a training session.
- Ended training session syncs to iPhone or remains pending sync on Watch.
- User can select a training session and then select a valid video.
- Invalid or metadata-missing videos are rejected.
- App clips marker - 10 seconds through marker + 3 seconds.
- Overlapping markers remain separate clips.
- Exported highlight preserves source audio.
- Saved highlight appears in Photos.
- Training session becomes marked as clipped after successful save.

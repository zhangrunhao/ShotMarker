# Filter Unusable Videos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Filter unavailable or unusable training videos immediately after selection so only videos that can generate clips remain visible and usable.

**Architecture:** Add one pure availability helper to `VideoClipSegmentPlanner` for fast marker coverage checks. Update `TrainingSessionHighlightView` to load selected videos one by one, skip videos that fail local readiness or marker coverage, and show one summary alert when anything is skipped.

**Tech Stack:** Swift, SwiftUI, PhotosUI, Photos, AVFoundation, XCTest, Xcode project tests.

---

## File Structure

- Modify `ShotMarker/Services/VideoClipSegmentPlanner.swift`
  - Add `canUseVideo(_:for:)`, a pure helper that checks duration validity and whether any marker falls inside a video's recorded time range.
- Create `ShotMarker/Services/SelectedTrainingVideoReadinessChecker.swift`
  - Add a tiny injectable readiness checker that skips local file URLs and verifies Photos asset identifiers through an async closure.
- Modify `ShotMarkerTests/VideoClipSegmentPlannerTests.swift`
  - Add focused tests for marker coverage, no coverage, invalid duration, and inclusive boundaries.
- Create `ShotMarkerTests/SelectedTrainingVideoReadinessCheckerTests.swift`
  - Add tests for local file skip, Photos asset verification, and readiness error propagation.
- Modify `ShotMarker/Views/TrainingSessionHighlightView.swift`
  - Keep the existing PhotosPicker UI.
  - Change `loadSelectedVideos(from:)` from fail-all behavior to per-item filtering.
  - Add local Photos asset readiness verification with network access disabled.
  - Add filtered video summary alert and summary logging.

## Task 1: Pure Video Availability Helper

**Files:**
- Modify: `ShotMarker/Services/VideoClipSegmentPlanner.swift`
- Test: `ShotMarkerTests/VideoClipSegmentPlannerTests.swift`

- [ ] **Step 1: Write failing tests**

Append these tests inside `final class VideoClipSegmentPlannerTests: XCTestCase`:

```swift
func testCanUseVideoReturnsTrueWhenVideoCoversMarker() throws {
    let marker = try ShotMarkerEvent(
        id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001501")),
        markedAt: Date(timeIntervalSince1970: 120),
    )
    let session = TrainingSession(
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 160),
        events: [marker],
    )
    let video = SelectedTrainingVideo(
        id: "video",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )

    XCTAssertTrue(VideoClipSegmentPlanner.canUseVideo(video, for: session))
}

func testCanUseVideoReturnsFalseWhenVideoCoversNoMarkers() throws {
    let marker = try ShotMarkerEvent(
        id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001502")),
        markedAt: Date(timeIntervalSince1970: 200),
    )
    let session = TrainingSession(
        startedAt: Date(timeIntervalSince1970: 180),
        endedAt: Date(timeIntervalSince1970: 220),
        events: [marker],
    )
    let video = SelectedTrainingVideo(
        id: "video",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )

    XCTAssertFalse(VideoClipSegmentPlanner.canUseVideo(video, for: session))
}

func testCanUseVideoTreatsBoundaryMarkersAsCovered() throws {
    let startMarker = try ShotMarkerEvent(
        id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001503")),
        markedAt: Date(timeIntervalSince1970: 100),
    )
    let endMarker = try ShotMarkerEvent(
        id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001504")),
        markedAt: Date(timeIntervalSince1970: 160),
    )
    let video = SelectedTrainingVideo(
        id: "video",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )

    let startSession = TrainingSession(
        startedAt: Date(timeIntervalSince1970: 90),
        endedAt: Date(timeIntervalSince1970: 110),
        events: [startMarker],
    )
    let endSession = TrainingSession(
        startedAt: Date(timeIntervalSince1970: 150),
        endedAt: Date(timeIntervalSince1970: 170),
        events: [endMarker],
    )

    XCTAssertTrue(VideoClipSegmentPlanner.canUseVideo(video, for: startSession))
    XCTAssertTrue(VideoClipSegmentPlanner.canUseVideo(video, for: endSession))
}

func testCanUseVideoReturnsFalseForInvalidDuration() throws {
    let marker = try ShotMarkerEvent(
        id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001505")),
        markedAt: Date(timeIntervalSince1970: 100),
    )
    let session = TrainingSession(
        startedAt: Date(timeIntervalSince1970: 90),
        endedAt: Date(timeIntervalSince1970: 110),
        events: [marker],
    )
    let zeroDurationVideo = SelectedTrainingVideo(
        id: "zero",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 0,
    )
    let infiniteDurationVideo = SelectedTrainingVideo(
        id: "infinite",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: .infinity,
    )

    XCTAssertFalse(VideoClipSegmentPlanner.canUseVideo(zeroDurationVideo, for: session))
    XCTAssertFalse(VideoClipSegmentPlanner.canUseVideo(infiniteDurationVideo, for: session))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests
```

Expected: build fails because `VideoClipSegmentPlanner.canUseVideo(_:for:)` does not exist.

- [ ] **Step 3: Add minimal implementation**

Add this method inside `enum VideoClipSegmentPlanner`, before `highlightPlan(for:videos:clipSettings:)`:

```swift
static func canUseVideo(
    _ video: SelectedTrainingVideo,
    for session: TrainingSession,
) -> Bool {
    guard video.duration.isFinite, video.duration > 0 else {
        return false
    }

    return session.events.contains { event in
        video.recordedStartAt <= event.markedAt && event.markedAt <= video.recordedEndAt
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests
```

Expected: `VideoClipSegmentPlannerTests` passes.

- [ ] **Step 5: Commit**

Run:

```bash
git add ShotMarker/Services/VideoClipSegmentPlanner.swift ShotMarkerTests/VideoClipSegmentPlannerTests.swift
git commit -m "feat: 添加训练视频可用性判断"
```

## Task 2: Selected Video Readiness Checker

**Files:**
- Create: `ShotMarker/Services/SelectedTrainingVideoReadinessChecker.swift`
- Test: `ShotMarkerTests/SelectedTrainingVideoReadinessCheckerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ShotMarkerTests/SelectedTrainingVideoReadinessCheckerTests.swift`:

```swift
@testable import ShotMarker
import XCTest

final class SelectedTrainingVideoReadinessCheckerTests: XCTestCase {
    func testEnsureReadySkipsLocalFileVideos() async throws {
        var verifiedAssetIdentifiers: [String] = []
        let checker = SelectedTrainingVideoReadinessChecker { assetIdentifier in
            verifiedAssetIdentifiers.append(assetIdentifier)
        }
        let video = SelectedTrainingVideo(
            id: URL(fileURLWithPath: "/tmp/video.mov").absoluteString,
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        try await checker.ensureReady(video)

        XCTAssertEqual(verifiedAssetIdentifiers, [])
    }

    func testEnsureReadyVerifiesPhotoLibraryAssetVideos() async throws {
        var verifiedAssetIdentifiers: [String] = []
        let checker = SelectedTrainingVideoReadinessChecker { assetIdentifier in
            verifiedAssetIdentifiers.append(assetIdentifier)
        }
        let video = SelectedTrainingVideo(
            id: "photo-library-asset-id",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        try await checker.ensureReady(video)

        XCTAssertEqual(verifiedAssetIdentifiers, ["photo-library-asset-id"])
    }

    func testEnsureReadyPropagatesPhotoLibraryReadinessFailure() async {
        let checker = SelectedTrainingVideoReadinessChecker { _ in
            throw ReadinessError.notReady
        }
        let video = SelectedTrainingVideo(
            id: "photo-library-asset-id",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        do {
            try await checker.ensureReady(video)
            XCTFail("Expected readiness failure")
        } catch {
            XCTAssertEqual(error as? ReadinessError, .notReady)
        }
    }

    private enum ReadinessError: Error, Equatable {
        case notReady
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/SelectedTrainingVideoReadinessCheckerTests
```

Expected: build fails because `SelectedTrainingVideoReadinessChecker` does not exist.

- [ ] **Step 3: Add minimal implementation**

Create `ShotMarker/Services/SelectedTrainingVideoReadinessChecker.swift`:

```swift
import Foundation

struct SelectedTrainingVideoReadinessChecker {
    typealias VerifyPhotoLibraryAssetIsLocal = (String) async throws -> Void

    private let verifyPhotoLibraryAssetIsLocal: VerifyPhotoLibraryAssetIsLocal

    init(verifyPhotoLibraryAssetIsLocal: @escaping VerifyPhotoLibraryAssetIsLocal) {
        self.verifyPhotoLibraryAssetIsLocal = verifyPhotoLibraryAssetIsLocal
    }

    func ensureReady(_ video: SelectedTrainingVideo) async throws {
        guard Self.temporaryVideoURL(from: video.id) == nil else {
            return
        }

        try await verifyPhotoLibraryAssetIsLocal(video.id)
    }

    static func temporaryVideoURL(from videoID: String) -> URL? {
        guard let url = URL(string: videoID), url.isFileURL else {
            return nil
        }

        return url
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/SelectedTrainingVideoReadinessCheckerTests
```

Expected: `SelectedTrainingVideoReadinessCheckerTests` passes.

- [ ] **Step 5: Commit**

Run:

```bash
git add ShotMarker/Services/SelectedTrainingVideoReadinessChecker.swift ShotMarkerTests/SelectedTrainingVideoReadinessCheckerTests.swift
git commit -m "feat: 添加训练视频就绪检查"
```

## Task 3: Filter Videos During Selection

**Files:**
- Modify: `ShotMarker/Views/TrainingSessionHighlightView.swift`

- [ ] **Step 1: Confirm tested helpers are available**

The integration must use these tested APIs:

```swift
VideoClipSegmentPlanner.canUseVideo(video, for: session)

SelectedTrainingVideoReadinessChecker { assetIdentifier in
    let asset = try photoAsset(with: assetIdentifier)
    try await requestLocalAVAsset(for: asset)
}
```

- [ ] **Step 2: Update selection loading to filter per item**

Replace the body of `loadSelectedVideos(from:)` with:

```swift
@MainActor
private func loadSelectedVideos(from items: [PhotosPickerItem]) async {
    cleanupTemporaryVideos()
    selectedVideos = []

    guard !items.isEmpty else {
        return
    }

    logger.info(
        "video.selection.started",
        category: .video,
        message: "开始读取所选视频",
        context: highlightContext(extra: ["requestedItemCount": "\(items.count)"]),
    )
    isLoadingVideos = true
    defer {
        isLoadingVideos = false
    }

    var videos: [SelectedTrainingVideo] = []
    var failedToLoadCount = 0
    var noMarkerCoverageCount = 0

    for (index, item) in items.enumerated() {
        do {
            let video = try await Self.loadSelectedVideo(from: item)

            guard VideoClipSegmentPlanner.canUseVideo(video, for: session) else {
                noMarkerCoverageCount += 1
                Self.removeTemporaryVideoIfNeeded(video)
                continue
            }

            try await Self.readyTrainingVideoChecker.ensureReady(video)
            videos.append(video)
            logger.info(
                "video.selection.item.loaded",
                category: .video,
                message: "已读取所选视频",
                context: highlightContext(extra: [
                    "itemIndex": "\(index + 1)",
                    "loadedVideoCount": "\(videos.count)",
                    "source": item.itemIdentifier == nil ? "pickerFile" : "photoLibrary",
                    "durationSeconds": Self.secondsString(video.duration),
                ]),
            )
        } catch {
            failedToLoadCount += 1
            logger.warning(
                "video.selection.item.filtered",
                category: .video,
                message: "已忽略不可用视频",
                context: highlightContext(extra: [
                    "itemIndex": "\(index + 1)",
                    "reason": "failedToLoad",
                ]),
            )
        }
    }

    selectedVideos = videos
    reportFilteredVideoSelectionIfNeeded(
        requestedItemCount: items.count,
        retainedVideoCount: videos.count,
        failedToLoadCount: failedToLoadCount,
        noMarkerCoverageCount: noMarkerCoverageCount,
    )
}
```

- [ ] **Step 3: Add summary reporter**

Add this instance method near `highlightPlanContext(_:extra:)`:

```swift
private func reportFilteredVideoSelectionIfNeeded(
    requestedItemCount: Int,
    retainedVideoCount: Int,
    failedToLoadCount: Int,
    noMarkerCoverageCount: Int,
) {
    let filteredVideoCount = failedToLoadCount + noMarkerCoverageCount
    guard filteredVideoCount > 0 else {
        return
    }

    logger.info(
        "video.selection.filtered",
        category: .video,
        message: "已过滤不可用视频",
        context: highlightContext(extra: [
            "requestedItemCount": "\(requestedItemCount)",
            "retainedVideoCount": "\(retainedVideoCount)",
            "filteredVideoCount": "\(filteredVideoCount)",
            "failedToLoadCount": "\(failedToLoadCount)",
            "noMarkerCoverageCount": "\(noMarkerCoverageCount)",
        ]),
    )

    if retainedVideoCount == 0 {
        selectedItems = []
        alert = HighlightFlowAlert(
            title: "没有可用视频",
            message: "没有可用于本次训练的视频。请确认视频已下载、包含拍摄时间，并覆盖本次训练时间。",
        )
    } else {
        alert = HighlightFlowAlert(
            title: "已忽略不可用视频",
            message: "已忽略 \(filteredVideoCount) 个不可用视频。请确认视频已下载、包含拍摄时间，并覆盖本次训练时间。",
        )
    }
}
```

- [ ] **Step 4: Add local readiness helpers**

Add this static property near the other static helpers:

```swift
nonisolated private static var readyTrainingVideoChecker: SelectedTrainingVideoReadinessChecker {
    SelectedTrainingVideoReadinessChecker { assetIdentifier in
        let asset = try photoAsset(with: assetIdentifier)
        try await requestLocalAVAsset(for: asset)
    }
}
```

Add this local Photos request helper near `requestAVAsset(for:deliveryQuality:)`:

```swift
nonisolated private static func requestLocalAVAsset(for asset: PHAsset) async throws {
    let options = PHVideoRequestOptions()
    options.deliveryMode = .mediumQualityFormat
    options.isNetworkAccessAllowed = false

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
            if let error = info?[PHImageErrorKey] as? Error {
                continuation.resume(throwing: error)
                return
            }

            if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                continuation.resume(throwing: HighlightVideoSelectionError.videoLoadFailed)
                return
            }

            guard avAsset != nil else {
                continuation.resume(throwing: HighlightVideoSelectionError.videoNotReady)
                return
            }

            continuation.resume()
        }
    }
}

nonisolated private static func removeTemporaryVideoIfNeeded(_ video: SelectedTrainingVideo) {
    guard let url = temporaryVideoURL(from: video.id) else {
        return
    }

    try? FileManager.default.removeItem(at: url)
}
```

Update the existing `temporaryVideoURL(from:)` helper to delegate to the tested readiness checker:

```swift
nonisolated private static func temporaryVideoURL(from videoID: String) -> URL? {
    SelectedTrainingVideoReadinessChecker.temporaryVideoURL(from: videoID)
}
```

- [ ] **Step 5: Add user-facing readiness error**

Add `case videoNotReady` to `HighlightVideoSelectionError`, then update `errorDescription`:

```swift
case .videoNotReady:
    "所选视频还没有下载完成，暂时无法用于自动剪辑。"
```

- [ ] **Step 6: Build and run targeted tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests
```

Expected: tests pass and `TrainingSessionHighlightView.swift` compiles.

- [ ] **Step 7: Run full iPhone test suite**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests
```

Expected: `ShotMarkerTests` passes.

- [ ] **Step 8: Commit**

Run:

```bash
git add ShotMarker/Views/TrainingSessionHighlightView.swift
git commit -m "feat: 过滤不可用训练视频"
```

## Self-Review

- Spec coverage: Task 1 covers the lightweight marker coverage helper. Task 2 covers the testable readiness checker used to skip local files and verify Photos assets. Task 3 covers per-item filtering, no network download during readiness verification, summary alerts, and summary logging.
- Placeholder scan: no placeholders remain.
- Type consistency: `SelectedTrainingVideo`, `TrainingSession`, `SelectedTrainingVideoReadinessChecker`, `PhotosPickerItem`, `PHAsset`, `HighlightVideoSelectionError`, and `HighlightFlowAlert` match existing code names.

# Highlight Flow Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align clip defaults with the confirmed PRD and split iPhone highlight video loading/preparation logic out of `TrainingSessionHighlightView` without changing user-visible flow.

**Architecture:** Keep `TrainingSessionHighlightView` as the SwiftUI orchestration layer. Move Photos/AVFoundation/Transferable details into `TrainingVideoLoadingService`, `PhotoLibraryVideoAssetProvider`, and `TrainingVideoTemporaryFileStore`; keep clip planning and export services unchanged except for default settings and clearer tests.

**Tech Stack:** Swift, SwiftUI, PhotosUI, Photos, AVFoundation, CoreTransferable, XCTest, Xcode schemes `ShotMarker` and `ShotMarkerWatchApp`.

---

## File Structure

- Modify `ShotMarker/Models/ClipSettings.swift`
  - Change `ClipSettings.default` from `5/2` to `9/4`.
- Modify `ShotMarkerTests/ClipSettingsStoreTests.swift`
  - Update default settings test name and assertion.
- Modify `ShotMarkerTests/VideoClipSegmentPlannerTests.swift`
  - Rename and extend the merge test so current merge behavior and `1-2/N` labels are explicit.
- Create `ShotMarker/Services/TrainingVideoLoadingService.swift`
  - Add testable selection loading orchestration.
  - Own `TrainingVideoMetadata`, `LoadedTrainingVideo`, `SelectedTrainingVideoLoadFailure`, and `HighlightVideoSelectionError`.
- Create `ShotMarkerTests/TrainingVideoLoadingServiceTests.swift`
  - Test loading decisions using fake selection items and injected closures.
- Create `ShotMarker/Services/TrainingVideoTemporaryFileStore.swift`
  - Move picker fallback file copy, temporary URL detection, temporary cleanup, local metadata, and local thumbnail generation.
- Create `ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift`
  - Move Photos read permission, PHAsset lookup, PHAsset metadata, PHAsset thumbnail, AVAsset request, local-readiness request, cancellation box, and delivery-quality mapping.
- Modify `ShotMarker/Views/TrainingSessionHighlightView.swift`
  - Inject and call the new services.
  - Remove moved platform helper code and private data types.

## Task 1: Clip Settings Default

**Files:**
- Modify: `ShotMarkerTests/ClipSettingsStoreTests.swift:20`
- Modify: `ShotMarker/Models/ClipSettings.swift:7`

- [ ] **Step 1: Write the failing default-settings test**

Replace the existing default test in `ShotMarkerTests/ClipSettingsStoreTests.swift` with:

```swift
func testDefaultClipSettingsUseNineSecondsBeforeAndFourSecondsAfterMarker() {
    XCTAssertEqual(ClipSettings.default, ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/ClipSettingsStoreTests/testDefaultClipSettingsUseNineSecondsBeforeAndFourSecondsAfterMarker
```

Expected: FAIL because `ClipSettings.default` is still `5/2`.

- [ ] **Step 3: Update the production default**

Change `ShotMarker/Models/ClipSettings.swift` to:

```swift
import Foundation

struct ClipSettings: Codable, Equatable {
    var secondsBeforeMarker: TimeInterval
    var secondsAfterMarker: TimeInterval

    static let `default` = ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4)
}
```

Keep the existing `ClipSettingsStore` implementation unchanged so user-modified settings continue to persist through `UserDefaults`.

- [ ] **Step 4: Run ClipSettings tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/ClipSettingsStoreTests
```

Expected: PASS for all `ClipSettingsStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add ShotMarker/Models/ClipSettings.swift ShotMarkerTests/ClipSettingsStoreTests.swift
git commit -m "fix: 更新默认剪辑时间窗口"
```

## Task 2: Segment Planner Regression Names

**Files:**
- Modify: `ShotMarkerTests/VideoClipSegmentPlannerTests.swift:93`

- [ ] **Step 1: Clarify the existing merge regression**

Rename `testHighlightPlanMergesOverlappingSegmentsForNearbyMarkers` to:

```swift
func testHighlightPlanMergesOverlappingSegmentsAndUsesMarkerRangeLabel() throws {
```

Keep the body equivalent to the current assertions:

```swift
XCTAssertEqual(plan.matchedMarkerCount, 2)
XCTAssertEqual(plan.unmatchedMarkerCount, 0)
XCTAssertEqual(plan.segments.first?.markerLabel, "1-2/2")
XCTAssertEqual(plan.segments.first?.coveredMarkerCount, 2)
XCTAssertEqual(plan.segments, [
    HighlightClipSegment(
        markerID: firstMarker.id,
        videoID: video.id,
        markerAt: firstMarker.markedAt,
        start: 4,
        duration: 12,
        markerNumberRange: 1...2,
        markerTotalCount: 2,
    ),
])
```

- [ ] **Step 2: Add a one-second-gap merge regression**

Add this test below the renamed overlap test:

```swift
func testHighlightPlanMergesSegmentsSeparatedByOneSecondGap() throws {
    let firstMarker = try ShotMarkerEvent(
        id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001601")),
        markedAt: Date(timeIntervalSince1970: 110),
    )
    let secondMarker = try ShotMarkerEvent(
        id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001602")),
        markedAt: Date(timeIntervalSince1970: 117),
    )
    let video = SelectedTrainingVideo(
        id: "video",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
    )
    let session = TrainingSession(
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 160),
        events: [secondMarker, firstMarker],
    )

    let plan = VideoClipSegmentPlanner.highlightPlan(
        for: session,
        videos: [video],
        clipSettings: ClipSettings(secondsBeforeMarker: 4, secondsAfterMarker: 2),
    )

    XCTAssertEqual(plan.matchedMarkerCount, 2)
    XCTAssertEqual(plan.segments.map(\.markerLabel), ["1-2/2"])
    XCTAssertEqual(plan.segments, [
        HighlightClipSegment(
            markerID: firstMarker.id,
            videoID: video.id,
            markerAt: firstMarker.markedAt,
            start: 6,
            duration: 13,
            markerNumberRange: 1...2,
            markerTotalCount: 2,
        ),
    ])
}
```

- [ ] **Step 3: Run planner tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests
```

Expected: PASS. This task documents existing intended behavior; production planner code should not change.

- [ ] **Step 4: Commit**

```bash
git add ShotMarkerTests/VideoClipSegmentPlannerTests.swift
git commit -m "test: 明确片段合并标签行为"
```

## Task 3: Testable Training Video Loading Service

**Files:**
- Create: `ShotMarker/Services/TrainingVideoLoadingService.swift`
- Create: `ShotMarkerTests/TrainingVideoLoadingServiceTests.swift`

- [ ] **Step 1: Write service tests first**

Create `ShotMarkerTests/TrainingVideoLoadingServiceTests.swift`:

```swift
#if os(iOS)
    @testable import ShotMarker
    import XCTest

    final class TrainingVideoLoadingServiceTests: XCTestCase {
        func testLoadSelectionItemReturnsMissingRecordedStartReason() async throws {
            let service = makeService(
                loadPhotoLibraryVideo: { assetIdentifier in
                    throw SelectedTrainingVideoLoadFailure(
                        id: assetIdentifier,
                        thumbnailData: Data([1, 2, 3]),
                        error: HighlightVideoSelectionError.missingRecordedStartAt,
                    )
                },
                loadPickedVideo: { _ in
                    throw HighlightVideoSelectionError.videoLoadFailed
                },
            )

            let item = await service.loadSelectionItem(
                from: "photo",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(item.id, "asset-id")
            XCTAssertEqual(item.unavailableReason, .missingRecordedStartAt)
            XCTAssertEqual(item.thumbnailData, Data([1, 2, 3]))
        }

        func testLoadSelectionItemReturnsInvalidDurationReason() async throws {
            let service = makeService(
                loadPhotoLibraryVideo: { assetIdentifier in
                    throw SelectedTrainingVideoLoadFailure(
                        id: assetIdentifier,
                        thumbnailData: nil,
                        error: HighlightVideoSelectionError.invalidDuration,
                    )
                },
                loadPickedVideo: { _ in
                    throw HighlightVideoSelectionError.videoLoadFailed
                },
            )

            let item = await service.loadSelectionItem(
                from: "photo",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(item.id, "asset-id")
            XCTAssertEqual(item.unavailableReason, .invalidDuration)
        }

        func testLoadSelectionItemFallsBackToPickedVideoWhenPhotoLibraryLoadFails() async throws {
            var pickedVideoLoadCount = 0
            let pickedVideo = SelectedTrainingVideo(
                id: URL(fileURLWithPath: "/tmp/picked.mov").absoluteString,
                recordedStartAt: Date(timeIntervalSince1970: 100),
                duration: 60,
            )
            let service = makeService(
                loadPhotoLibraryVideo: { _ in
                    throw HighlightVideoSelectionError.photoLibraryAccessDenied
                },
                loadPickedVideo: { _ in
                    pickedVideoLoadCount += 1
                    return LoadedTrainingVideo(video: pickedVideo, thumbnailData: Data([9]))
                },
            )

            let item = await service.loadSelectionItem(
                from: "photo",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(pickedVideoLoadCount, 1)
            XCTAssertTrue(item.isAvailable)
            XCTAssertEqual(item.video, pickedVideo)
            XCTAssertEqual(item.thumbnailData, Data([9]))
        }

        func testLoadSelectionItemReturnsNoMarkerCoverageAndRemovesTemporaryVideo() async throws {
            var removedVideoIDs: [String] = []
            let pickedVideo = SelectedTrainingVideo(
                id: URL(fileURLWithPath: "/tmp/out-of-range.mov").absoluteString,
                recordedStartAt: Date(timeIntervalSince1970: 300),
                duration: 60,
            )
            let service = makeService(
                assetIdentifier: { _ in nil },
                loadPhotoLibraryVideo: { _ in
                    throw HighlightVideoSelectionError.videoLoadFailed
                },
                loadPickedVideo: { _ in
                    LoadedTrainingVideo(video: pickedVideo, thumbnailData: Data([4]))
                },
                removeTemporaryVideoIfNeeded: { video in
                    removedVideoIDs.append(video.id)
                },
            )

            let item = await service.loadSelectionItem(
                from: "picked",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(item.id, pickedVideo.id)
            XCTAssertEqual(item.unavailableReason, .noMarkerCoverage)
            XCTAssertEqual(item.thumbnailData, Data([4]))
            XCTAssertEqual(removedVideoIDs, [pickedVideo.id])
        }

        func testLoadSelectionItemReturnsNotReadyWithVideoForPreparation() async throws {
            let video = SelectedTrainingVideo(
                id: "asset-id",
                recordedStartAt: Date(timeIntervalSince1970: 100),
                duration: 60,
            )
            let service = makeService(
                loadPhotoLibraryVideo: { _ in
                    LoadedTrainingVideo(video: video, thumbnailData: Data([5]))
                },
                loadPickedVideo: { _ in
                    throw HighlightVideoSelectionError.videoLoadFailed
                },
                ensureReady: { _ in
                    throw HighlightVideoSelectionError.videoNotReady
                },
            )

            let item = await service.loadSelectionItem(
                from: "photo",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(item.id, video.id)
            XCTAssertEqual(item.video, video)
            XCTAssertEqual(item.unavailableReason, .notReady)
            XCTAssertEqual(item.thumbnailData, Data([5]))
        }

        private func makeService(
            assetIdentifier: @escaping (String) -> String? = { item in item == "photo" ? "asset-id" : nil },
            loadPhotoLibraryVideo: @escaping (String) async throws -> LoadedTrainingVideo,
            loadPickedVideo: @escaping (String) async throws -> LoadedTrainingVideo,
            ensureReady: @escaping (SelectedTrainingVideo) async throws -> Void = { _ in },
            removeTemporaryVideoIfNeeded: @escaping (SelectedTrainingVideo) -> Void = { _ in },
        ) -> TrainingVideoLoadingService<String> {
            TrainingVideoLoadingService<String>(
                assetIdentifier: assetIdentifier,
                loadPhotoLibraryVideo: loadPhotoLibraryVideo,
                loadPickedVideo: loadPickedVideo,
                ensureReady: ensureReady,
                removeTemporaryVideoIfNeeded: removeTemporaryVideoIfNeeded,
            )
        }

        private func makeSession() -> TrainingSession {
            TrainingSession(
                startedAt: Date(timeIntervalSince1970: 90),
                endedAt: Date(timeIntervalSince1970: 150),
                events: [
                    ShotMarkerEvent(markedAt: Date(timeIntervalSince1970: 120)),
                ],
            )
        }
    }
#endif
```

- [ ] **Step 2: Run the new test file and verify it fails to compile**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/TrainingVideoLoadingServiceTests
```

Expected: FAIL because `TrainingVideoLoadingService`, `LoadedTrainingVideo`, `SelectedTrainingVideoLoadFailure`, and `HighlightVideoSelectionError` do not exist yet.

- [ ] **Step 3: Add the service implementation**

Create `ShotMarker/Services/TrainingVideoLoadingService.swift`:

```swift
#if os(iOS)
    import Foundation
    import PhotosUI

    struct TrainingVideoMetadata {
        let recordedStartAt: Date
        let duration: TimeInterval
    }

    struct LoadedTrainingVideo {
        let video: SelectedTrainingVideo
        let thumbnailData: Data?
    }

    struct SelectedTrainingVideoLoadFailure: Error {
        let id: String
        let thumbnailData: Data?
        let error: Error
    }

    enum HighlightVideoSelectionError: LocalizedError {
        case videoLoadFailed
        case photoLibraryAccessDenied
        case missingRecordedStartAt
        case invalidDuration
        case videoNotReady

        var errorDescription: String? {
            switch self {
            case .videoLoadFailed:
                "无法读取选择的视频。"
            case .photoLibraryAccessDenied:
                "没有相册读取权限。请允许 ShotMarker 读取所选视频后再试。"
            case .missingRecordedStartAt:
                "所选视频缺少拍摄时间，暂时无法用于自动剪辑。"
            case .invalidDuration:
                "所选视频无法读取时长，请重新选择其他视频。"
            case .videoNotReady:
                "所选视频还没有下载完成，暂时无法用于自动剪辑。"
            }
        }
    }

    struct TrainingVideoLoadingService<SelectionItem> {
        private let assetIdentifier: (SelectionItem) -> String?
        private let loadPhotoLibraryVideo: (String) async throws -> LoadedTrainingVideo
        private let loadPickedVideo: (SelectionItem) async throws -> LoadedTrainingVideo
        private let ensureReady: (SelectedTrainingVideo) async throws -> Void
        private let removeTemporaryVideoIfNeeded: (SelectedTrainingVideo) -> Void

        init(
            assetIdentifier: @escaping (SelectionItem) -> String?,
            loadPhotoLibraryVideo: @escaping (String) async throws -> LoadedTrainingVideo,
            loadPickedVideo: @escaping (SelectionItem) async throws -> LoadedTrainingVideo,
            ensureReady: @escaping (SelectedTrainingVideo) async throws -> Void,
            removeTemporaryVideoIfNeeded: @escaping (SelectedTrainingVideo) -> Void,
        ) {
            self.assetIdentifier = assetIdentifier
            self.loadPhotoLibraryVideo = loadPhotoLibraryVideo
            self.loadPickedVideo = loadPickedVideo
            self.ensureReady = ensureReady
            self.removeTemporaryVideoIfNeeded = removeTemporaryVideoIfNeeded
        }

        func loadSelectionItem(
            from item: SelectionItem,
            title: String,
            fallbackID: String,
            session: TrainingSession,
        ) async -> SelectedTrainingVideoSelectionItem {
            do {
                let loadedVideo = try await loadVideo(from: item, fallbackID: fallbackID)
                guard VideoClipSegmentPlanner.canUseVideo(loadedVideo.video, for: session) else {
                    removeTemporaryVideoIfNeeded(loadedVideo.video)
                    return .unavailable(
                        id: loadedVideo.video.id,
                        title: title,
                        reason: .noMarkerCoverage,
                        thumbnailData: loadedVideo.thumbnailData,
                    )
                }

                do {
                    try await ensureReady(loadedVideo.video)
                } catch {
                    return .unavailable(
                        id: loadedVideo.video.id,
                        title: title,
                        video: loadedVideo.video,
                        reason: .notReady,
                        thumbnailData: loadedVideo.thumbnailData,
                    )
                }

                return .available(
                    id: loadedVideo.video.id,
                    title: title,
                    video: loadedVideo.video,
                    thumbnailData: loadedVideo.thumbnailData,
                )
            } catch let failure as SelectedTrainingVideoLoadFailure {
                return .unavailable(
                    id: failure.id,
                    title: title,
                    reason: Self.unavailableReason(for: failure.error),
                    thumbnailData: failure.thumbnailData,
                )
            } catch {
                return .unavailable(
                    id: assetIdentifier(item) ?? fallbackID,
                    title: title,
                    reason: Self.unavailableReason(for: error),
                    thumbnailData: nil,
                )
            }
        }

        private func loadVideo(
            from item: SelectionItem,
            fallbackID: String,
        ) async throws -> LoadedTrainingVideo {
            var photoLibraryFailure: SelectedTrainingVideoLoadFailure?

            if let assetIdentifier = assetIdentifier(item) {
                do {
                    return try await loadPhotoLibraryVideo(assetIdentifier)
                } catch let failure as SelectedTrainingVideoLoadFailure {
                    photoLibraryFailure = failure
                } catch {
                    photoLibraryFailure = SelectedTrainingVideoLoadFailure(
                        id: assetIdentifier,
                        thumbnailData: nil,
                        error: error,
                    )
                }
            }

            do {
                return try await loadPickedVideo(item)
            } catch let failure as SelectedTrainingVideoLoadFailure {
                throw failure
            } catch {
                throw photoLibraryFailure ?? SelectedTrainingVideoLoadFailure(
                    id: assetIdentifier(item) ?? fallbackID,
                    thumbnailData: nil,
                    error: error,
                )
            }
        }

        private static func unavailableReason(for error: Error) -> SelectedTrainingVideoUnavailableReason {
            switch error as? HighlightVideoSelectionError {
            case .videoLoadFailed:
                .failedToLoad
            case .photoLibraryAccessDenied:
                .photoLibraryAccessDenied
            case .missingRecordedStartAt:
                .missingRecordedStartAt
            case .invalidDuration:
                .invalidDuration
            case .videoNotReady:
                .notReady
            case nil:
                .failedToLoad
            }
        }
    }
#endif
```

- [ ] **Step 4: Run service tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/TrainingVideoLoadingServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ShotMarker/Services/TrainingVideoLoadingService.swift ShotMarkerTests/TrainingVideoLoadingServiceTests.swift
git commit -m "test: 覆盖训练视频加载决策"
```

## Task 4: Temporary File Store Extraction

**Files:**
- Create: `ShotMarker/Services/TrainingVideoTemporaryFileStore.swift`
- Used by Task 6: `ShotMarker/Views/TrainingSessionHighlightView.swift`

- [ ] **Step 1: Add temporary file store**

Create `ShotMarker/Services/TrainingVideoTemporaryFileStore.swift`:

```swift
#if os(iOS)
    import AVFoundation
    import CoreTransferable
    import Foundation
    import PhotosUI
    import UIKit
    import UniformTypeIdentifiers

    struct TrainingVideoTemporaryFileStore {
        func loadPickedTrainingVideo(from item: PhotosPickerItem) async throws -> PickedTrainingVideo {
            guard let pickedVideo = try await item.loadTransferable(type: PickedTrainingVideo.self) else {
                throw HighlightVideoSelectionError.videoLoadFailed
            }

            return pickedVideo
        }

        func temporaryVideoURL(from videoID: String) -> URL? {
            SelectedTrainingVideoReadinessChecker.temporaryVideoURL(from: videoID)
        }

        func removeTemporaryVideoIfNeeded(_ video: SelectedTrainingVideo) {
            guard let url = temporaryVideoURL(from: video.id) else {
                return
            }

            removeTemporaryVideo(at: url)
        }

        func cleanupTemporaryVideos(_ videos: [SelectedTrainingVideo]) {
            videos.compactMap { temporaryVideoURL(from: $0.id) }.forEach(removeTemporaryVideo)
        }

        func removeTemporaryVideo(at url: URL) {
            try? FileManager.default.removeItem(at: url)
        }

        func metadata(from url: URL) async throws -> TrainingVideoMetadata {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds

            guard duration.isFinite, duration > 0 else {
                throw HighlightVideoSelectionError.invalidDuration
            }

            guard let creationDateItem = try await asset.load(.creationDate),
                  let recordedStartAt = try await creationDateItem.load(.dateValue)
            else {
                throw HighlightVideoSelectionError.missingRecordedStartAt
            }

            return TrainingVideoMetadata(recordedStartAt: recordedStartAt, duration: duration)
        }

        func thumbnailData(from url: URL) async -> Data? {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)

            do {
                let image = try await cgImage(from: generator, at: .zero)
                return UIImage(cgImage: image).jpegData(compressionQuality: 0.72)
            } catch {
                return nil
            }
        }

        private func cgImage(
            from generator: AVAssetImageGenerator,
            at time: CMTime,
        ) async throws -> CGImage {
            try await withCheckedThrowingContinuation { continuation in
                generator.generateCGImageAsynchronously(for: time) { image, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let image else {
                        continuation.resume(throwing: HighlightVideoSelectionError.videoLoadFailed)
                        return
                    }

                    continuation.resume(returning: image)
                }
            }
        }
    }

    struct PickedTrainingVideo: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { video in
                SentTransferredFile(video.url)
            } importing: { received in
                let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
                let copyURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ShotMarker-TrainingVideo-\(UUID().uuidString).\(fileExtension)")

                let isAccessingSecurityScopedResource = received.file.startAccessingSecurityScopedResource()
                defer {
                    if isAccessingSecurityScopedResource {
                        received.file.stopAccessingSecurityScopedResource()
                    }
                }

                try FileManager.default.copyItem(at: received.file, to: copyURL)
                return PickedTrainingVideo(url: copyURL)
            }
        }
    }
#endif
```

- [ ] **Step 2: Build iPhone target**

Run:

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS. The new file is not wired into the View yet, so this verifies the temporary-file extraction compiles without changing behavior.

## Task 5: Photo Library Asset Provider Extraction

**Files:**
- Create: `ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift`
- Used by Task 6: `ShotMarker/Views/TrainingSessionHighlightView.swift`

- [ ] **Step 1: Add Photos asset provider**

Create `ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift`:

```swift
#if os(iOS)
    import AVFoundation
    import Foundation
    import Photos
    import UIKit

    struct PhotoLibraryVideoAssetProvider {
        func ensureReadAccess() async throws {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            switch status {
            case .authorized, .limited:
                return
            case .notDetermined:
                let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                guard requestedStatus == .authorized || requestedStatus == .limited else {
                    throw HighlightVideoSelectionError.photoLibraryAccessDenied
                }
            case .denied, .restricted:
                throw HighlightVideoSelectionError.photoLibraryAccessDenied
            @unknown default:
                throw HighlightVideoSelectionError.photoLibraryAccessDenied
            }
        }

        func photoAsset(with localIdentifier: String) throws -> PHAsset {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = result.firstObject else {
                throw HighlightVideoSelectionError.videoLoadFailed
            }

            return asset
        }

        func metadata(from asset: PHAsset) throws -> TrainingVideoMetadata {
            guard let recordedStartAt = asset.creationDate else {
                throw HighlightVideoSelectionError.missingRecordedStartAt
            }

            guard asset.duration.isFinite, asset.duration > 0 else {
                throw HighlightVideoSelectionError.invalidDuration
            }

            return TrainingVideoMetadata(recordedStartAt: recordedStartAt, duration: asset.duration)
        }

        func thumbnailData(from asset: PHAsset) async -> Data? {
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true

            var thumbnailData: Data?
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 320, height: 180),
                contentMode: .aspectFill,
                options: options,
            ) { image, _ in
                thumbnailData = image?.jpegData(compressionQuality: 0.72)
            }
            return thumbnailData
        }

        func requestAVAsset(
            for asset: PHAsset,
            deliveryQuality: HighlightClipPhotoLibraryDeliveryQuality,
            progressHandler: (@Sendable (Double) -> Void)? = nil,
        ) async throws -> AVAsset {
            let options = PHVideoRequestOptions()
            options.deliveryMode = deliveryQuality.photoVideoRequestDeliveryMode
            options.isNetworkAccessAllowed = true
            if let progressHandler {
                options.progressHandler = { progress, _, _, _ in
                    progressHandler(progress)
                }
            }

            let cancellationBox = PhotoLibraryAssetRequestCancellationBox()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let requestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                        if let error = info?[PHImageErrorKey] as? Error {
                            continuation.resume(throwing: error)
                            return
                        }

                        if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        guard let avAsset else {
                            continuation.resume(throwing: HighlightVideoSelectionError.videoLoadFailed)
                            return
                        }

                        continuation.resume(returning: avAsset)
                    }
                    cancellationBox.setRequestID(requestID)
                }
            } onCancel: {
                cancellationBox.cancel()
            }
        }

        func requestLocalAVAsset(for asset: PHAsset) async throws {
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
    }

    extension HighlightClipPhotoLibraryDeliveryQuality {
        nonisolated var photoVideoRequestDeliveryMode: PHVideoRequestOptionsDeliveryMode {
            switch self {
            case .high:
                .highQualityFormat
            case .medium:
                .mediumQualityFormat
            }
        }
    }

    nonisolated private final class PhotoLibraryAssetRequestCancellationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var requestID = PHInvalidImageRequestID
        private var isCancelled = false

        func setRequestID(_ requestID: PHImageRequestID) {
            lock.lock()
            if isCancelled {
                lock.unlock()
                PHImageManager.default().cancelImageRequest(requestID)
                return
            }

            self.requestID = requestID
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let currentRequestID = requestID
            lock.unlock()

            guard currentRequestID != PHInvalidImageRequestID else {
                return
            }

            PHImageManager.default().cancelImageRequest(currentRequestID)
        }
    }
#endif
```

- [ ] **Step 2: Build iPhone target**

Run:

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS if the new provider compiles. If Swift reports a duplicate `photoVideoRequestDeliveryMode` member from the private View extension, move Task 6 Step 6 before this build and then rerun this same command.

## Task 6: Wire Services Into TrainingSessionHighlightView

**Files:**
- Modify: `ShotMarker/Services/TrainingVideoLoadingService.swift`
- Modify: `ShotMarker/Views/TrainingSessionHighlightView.swift`

- [ ] **Step 1: Add the PhotosPicker live factory**

Append this extension to `ShotMarker/Services/TrainingVideoLoadingService.swift`:

```swift
extension TrainingVideoLoadingService where SelectionItem == PhotosPickerItem {
    static func live(
        photoLibraryAssetProvider: PhotoLibraryVideoAssetProvider,
        temporaryFileStore: TrainingVideoTemporaryFileStore,
    ) -> TrainingVideoLoadingService<PhotosPickerItem> {
        let readinessChecker = SelectedTrainingVideoReadinessChecker { assetIdentifier in
            let asset = try photoLibraryAssetProvider.photoAsset(with: assetIdentifier)
            try await photoLibraryAssetProvider.requestLocalAVAsset(for: asset)
        }

        return TrainingVideoLoadingService<PhotosPickerItem>(
            assetIdentifier: { $0.itemIdentifier },
            loadPhotoLibraryVideo: { assetIdentifier in
                try await photoLibraryAssetProvider.ensureReadAccess()
                let asset = try photoLibraryAssetProvider.photoAsset(with: assetIdentifier)
                let thumbnailData = await photoLibraryAssetProvider.thumbnailData(from: asset)
                do {
                    let metadata = try photoLibraryAssetProvider.metadata(from: asset)
                    return LoadedTrainingVideo(
                        video: SelectedTrainingVideo(
                            id: asset.localIdentifier,
                            recordedStartAt: metadata.recordedStartAt,
                            duration: metadata.duration,
                        ),
                        thumbnailData: thumbnailData,
                    )
                } catch {
                    throw SelectedTrainingVideoLoadFailure(
                        id: assetIdentifier,
                        thumbnailData: thumbnailData,
                        error: error,
                    )
                }
            },
            loadPickedVideo: { item in
                let pickedVideo = try await temporaryFileStore.loadPickedTrainingVideo(from: item)
                let thumbnailData = await temporaryFileStore.thumbnailData(from: pickedVideo.url)
                do {
                    let metadata = try await temporaryFileStore.metadata(from: pickedVideo.url)
                    return LoadedTrainingVideo(
                        video: SelectedTrainingVideo(
                            id: pickedVideo.url.absoluteString,
                            recordedStartAt: metadata.recordedStartAt,
                            duration: metadata.duration,
                        ),
                        thumbnailData: thumbnailData,
                    )
                } catch {
                    temporaryFileStore.removeTemporaryVideo(at: pickedVideo.url)
                    throw SelectedTrainingVideoLoadFailure(
                        id: pickedVideo.url.absoluteString,
                        thumbnailData: thumbnailData,
                        error: error,
                    )
                }
            },
            ensureReady: { video in
                try await readinessChecker.ensureReady(video)
            },
            removeTemporaryVideoIfNeeded: { video in
                temporaryFileStore.removeTemporaryVideoIfNeeded(video)
            },
        )
    }
}
```

- [ ] **Step 2: Add service properties**

Add these stored properties next to the existing service properties:

```swift
private let videoLoadingService: TrainingVideoLoadingService<PhotosPickerItem>
private let photoLibraryAssetProvider: PhotoLibraryVideoAssetProvider
private let temporaryFileStore: TrainingVideoTemporaryFileStore
```

Update `init(session:logger:)` to construct and assign the services:

```swift
init(session: TrainingSession, logger: AppLogging = AppLogger.shared) {
    self.session = session
    self.logger = logger

    let photoLibraryAssetProvider = PhotoLibraryVideoAssetProvider()
    let temporaryFileStore = TrainingVideoTemporaryFileStore()
    self.photoLibraryAssetProvider = photoLibraryAssetProvider
    self.temporaryFileStore = temporaryFileStore
    videoLoadingService = TrainingVideoLoadingService.live(
        photoLibraryAssetProvider: photoLibraryAssetProvider,
        temporaryFileStore: temporaryFileStore,
    )
    editingService = VideoClipEditingService(logger: logger)
    photoLibrarySaver = VideoClipPhotoLibrarySaver(logger: logger)
}
```

- [ ] **Step 3: Route video preparation through `PhotoLibraryVideoAssetProvider`**

Replace `Self.preparePhotoLibraryVideo(video)` inside `prepareSelectedVideoItem` with:

```swift
let asset = try photoLibraryAssetProvider.photoAsset(with: video.id)
_ = try await photoLibraryAssetProvider.requestAVAsset(
    for: asset,
    deliveryQuality: .high,
    progressHandler: { progress in
        Task { @MainActor in
            updatePreparationProgress(for: itemID, runID: runID, progress: progress)
        }
    },
)
```

Remove the old wrapper call:

```swift
try await Self.preparePhotoLibraryVideo(video) { progress in
    Task { @MainActor in
        updatePreparationProgress(for: itemID, runID: runID, progress: progress)
    }
}
```

- [ ] **Step 4: Route selected video loading through `TrainingVideoLoadingService`**

Replace the body of `loadSelectedVideoItem(from:at:)` with:

```swift
let title = "视频 \(index + 1)"
let fallbackID = "selection-\(index + 1)"
return await videoLoadingService.loadSelectionItem(
    from: item,
    title: title,
    fallbackID: fallbackID,
    session: session,
)
```

- [ ] **Step 5: Route temporary cleanup through `TrainingVideoTemporaryFileStore`**

Replace the two cleanup helpers with:

```swift
private func cleanupTemporaryVideos() {
    temporaryFileStore.cleanupTemporaryVideos(selectedVideos)
}

private func cleanupTemporaryVideos(_ videos: [SelectedTrainingVideo]) {
    temporaryFileStore.cleanupTemporaryVideos(videos)
}
```

- [ ] **Step 6: Route asset provider in `generateHighlight`**

Replace the read-access check:

```swift
if Self.requiresPhotoLibraryReadAccess(for: segments) {
    try await Self.ensurePhotoLibraryReadAccess()
}
```

with:

```swift
if requiresPhotoLibraryReadAccess(for: segments) {
    try await photoLibraryAssetProvider.ensureReadAccess()
}
```

Replace the asset provider closure inside `makeHighlightClip` with:

```swift
if let fileURL = temporaryFileStore.temporaryVideoURL(from: request.videoID) {
    return AVURLAsset(url: fileURL)
}

let asset = try photoLibraryAssetProvider.photoAsset(with: request.videoID)
do {
    return try await photoLibraryAssetProvider.requestAVAsset(
        for: asset,
        deliveryQuality: request.photoLibraryDeliveryQuality(
            forSourceDuration: asset.duration,
        ),
    )
} catch {
    guard PhotoLibraryVideoAccess.shouldFallbackToPickerFile(for: error),
          let pickerItem = pickerItemsByAssetIdentifier[request.videoID]
    else {
        throw PhotoLibraryVideoAccess.userFacingError(for: error)
    }

    logger.warning(
        "video.asset.fallback_to_picker_file",
        category: .video,
        message: "改用选择器临时文件读取视频",
        context: highlightContext(extra: [
            "requestedDurationSeconds": Self.secondsString(request.requestedDuration),
        ]),
    )
    let pickedVideo = try await temporaryFileStore.loadPickedTrainingVideo(from: pickerItem)
    fallbackTemporaryVideoURLs.append(pickedVideo.url)
    return AVURLAsset(url: pickedVideo.url)
}
```

Add this instance helper near `pickerItemsByAssetIdentifier`:

```swift
private func requiresPhotoLibraryReadAccess(for segments: [HighlightClipSegment]) -> Bool {
    segments.contains { temporaryFileStore.temporaryVideoURL(from: $0.videoID) == nil }
}
```

- [ ] **Step 7: Remove moved helper code from the View**

Delete these definitions from `TrainingSessionHighlightView.swift` after all callers have moved:

```swift
loadSelectedVideoWithThumbnail(from:fallbackID:)
ensurePhotoLibraryReadAccess()
photoAsset(with:)
loadVideoMetadata(from asset:)
loadVideoMetadata(from url:)
thumbnailData(from asset:)
thumbnailData(from url:)
cgImage(from:at:)
readyTrainingVideoChecker
preparePhotoLibraryVideo(_:progressHandler:)
requestAVAsset(for:deliveryQuality:progressHandler:)
requestLocalAVAsset(for:)
loadTemporaryVideoURL(from:)
loadPickedTrainingVideo(from:)
temporaryVideoURL(from:)
removeTemporaryVideoIfNeeded(_:)
requiresPhotoLibraryReadAccess(for:)
unavailableReason(for:)
private extension HighlightClipPhotoLibraryDeliveryQuality
private struct TrainingVideoMetadata
private struct LoadedTrainingVideo
private struct SelectedTrainingVideoLoadFailure
PhotoLibraryAssetRequestCancellationBox
PickedTrainingVideo
HighlightVideoSelectionError
```

Keep these View-local definitions:

```swift
private static func secondsString(_ value: TimeInterval) -> String
private static func pickerItemsByAssetIdentifier(from items: [PhotosPickerItem]) -> [String: PhotosPickerItem]
private struct HighlightFlowAlert
```

- [ ] **Step 8: Build the iPhone app**

Run:

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS.

- [ ] **Step 9: Run focused tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/TrainingVideoLoadingServiceTests -only-testing:ShotMarkerTests/SelectedTrainingVideoReadinessCheckerTests -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests -only-testing:ShotMarkerTests/ClipSettingsStoreTests
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add ShotMarker/Views/TrainingSessionHighlightView.swift ShotMarker/Services/TrainingVideoLoadingService.swift ShotMarker/Services/TrainingVideoTemporaryFileStore.swift ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift ShotMarkerTests/TrainingVideoLoadingServiceTests.swift
git commit -m "refactor: 拆分集锦视频加载流程"
```

## Task 7: Full Verification

**Files:**
- No source edits expected.

- [ ] **Step 1: Run full iPhone tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [ ] **Step 2: Run full Watch tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'
```

Expected: PASS with `** TEST SUCCEEDED **`.

- [ ] **Step 3: Check worktree**

Run:

```bash
git status --short
```

Expected: no output.

- [ ] **Step 4: Inspect final file sizes**

Run:

```bash
wc -l ShotMarker/Views/TrainingSessionHighlightView.swift ShotMarker/Services/TrainingVideoLoadingService.swift ShotMarker/Services/TrainingVideoTemporaryFileStore.swift ShotMarker/Services/PhotoLibraryVideoAssetProvider.swift
```

Expected: `TrainingSessionHighlightView.swift` is substantially smaller than the starting 1281 lines, and platform loading code lives in the new service files.

# Highlight Job Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move highlight generation into a persistent home-screen job queue with cancellable progress, completed-video playback, and restartable interrupted jobs.

**Architecture:** Add a local `HighlightJob` domain with JSON persistence, durable input/output file storage, a serial `HighlightJobManager`, and a `HighlightJobRunner` that reuses the existing clip planner/export/save services. `TrainingSessionHighlightView` becomes a job creator, while `TrainingSessionListView` owns the queue UI and system-player presentation.

**Tech Stack:** Swift, SwiftUI, AVFoundation, Photos, PhotosUI, XCTest, Xcode filesystem-synchronized groups.

---

## File Structure

- Create `ShotMarker/Models/HighlightJob.swift`
  - Codable job, job video, status, progress, and display helpers.
- Create `ShotMarker/Services/HighlightJobStore.swift`
  - JSON persistence for job list and launch-time interruption recovery.
- Create `ShotMarker/Services/HighlightJobFileStore.swift`
  - Durable input/output file copy, move, lookup, and cleanup.
- Create `ShotMarker/Services/HighlightJobRunner.swift`
  - Run one job from plan calculation through local output and Photos save.
- Create `ShotMarker/ViewModels/HighlightJobManager.swift`
  - `@MainActor ObservableObject` queue coordinator for create, cancel, restart, clear, and serial execution.
- Create `ShotMarker/ViewModels/HighlightJobRowViewData.swift`
  - Small testable mapper for task row titles, status text, progress, and available actions.
- Create `ShotMarker/Views/HighlightJobListSection.swift`
  - Home-screen task list section with progress, cancel, restart, play, and clear buttons.
- Create `ShotMarker/Views/HighlightJobVideoPlayerView.swift`
  - UIKit-backed system player wrapper for completed local videos.
- Modify `ShotMarker/Services/VideoClipEditingService.swift`
  - Add export cancellation hook and injectible export closures for tests.
- Modify `ShotMarker/ShotMarkerApp.swift`
  - Construct a shared `HighlightJobManager` and load jobs on launch.
- Modify `ShotMarker/ContentView.swift`
  - Inject the shared job manager into the list view.
- Modify `ShotMarker/Views/TrainingSessionListView.swift`
  - Render `HighlightJobListSection` above training rows and present completed-video player.
- Modify `ShotMarker/Views/TrainingSessionHighlightView.swift`
  - Create a job instead of running export in-page; dismiss back to home.
- Add tests:
  - `ShotMarkerTests/HighlightJobStoreTests.swift`
  - `ShotMarkerTests/HighlightJobFileStoreTests.swift`
  - `ShotMarkerTests/HighlightJobRunnerTests.swift`
  - `ShotMarkerTests/HighlightJobManagerTests.swift`
  - `ShotMarkerTests/HighlightJobRowViewDataTests.swift`
  - Extend `ShotMarkerTests/VideoClipEditingServiceTests.swift`

Xcode uses filesystem-synchronized groups, so new Swift files under `ShotMarker` and `ShotMarkerTests` should be picked up without manual `.pbxproj` edits. Verify by running focused tests after each task.

## Task 1: Highlight Job Model And Store

**Files:**
- Create: `ShotMarker/Models/HighlightJob.swift`
- Create: `ShotMarker/Services/HighlightJobStore.swift`
- Create: `ShotMarkerTests/HighlightJobStoreTests.swift`

- [ ] **Step 1: Write the failing store tests**

Create `ShotMarkerTests/HighlightJobStoreTests.swift`:

```swift
@testable import ShotMarker
import XCTest

final class HighlightJobStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testLoadReturnsEmptyArrayWhenFileDoesNotExist() throws {
        let store = HighlightJobStore(fileURL: temporaryDirectory.appendingPathComponent("missing.json"))

        XCTAssertEqual(try store.loadJobs(), [])
    }

    func testSaveAndLoadRoundTripsJobs() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("highlight-jobs.json")
        let store = HighlightJobStore(fileURL: fileURL)
        let job = try makeJob(status: .completed)

        try store.saveJobs([job])

        XCTAssertEqual(try store.loadJobs(), [job])
    }

    func testLoadMarksLaunchInterruptedStatusesAsInterrupted() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("highlight-jobs.json")
        let store = HighlightJobStore(fileURL: fileURL)
        let queued = try makeJob(id: "00000000-0000-0000-0000-000000010001", status: .queued)
        let running = try makeJob(id: "00000000-0000-0000-0000-000000010002", status: .running)
        let saving = try makeJob(id: "00000000-0000-0000-0000-000000010003", status: .saving)
        let completed = try makeJob(id: "00000000-0000-0000-0000-000000010004", status: .completed)
        let failed = try makeJob(id: "00000000-0000-0000-0000-000000010005", status: .failed)
        let interrupted = try makeJob(id: "00000000-0000-0000-0000-000000010006", status: .interrupted)
        try store.saveJobs([queued, running, saving, completed, failed, interrupted])

        let loaded = try store.loadJobsForLaunchRecovery()

        XCTAssertEqual(loaded.map(\.status), [
            .interrupted,
            .interrupted,
            .interrupted,
            .completed,
            .failed,
            .interrupted,
        ])
        XCTAssertEqual(loaded[0].progress, queued.progress)
        XCTAssertNil(loaded[0].errorMessage)
    }

    func testJobEncodingUsesExpectedTopLevelKeys() throws {
        let job = try makeJob(status: .completed)

        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])

        XCTAssertEqual(
            Set(jsonObject.keys),
            Set([
                "id",
                "trainingSession",
                "selectedVideos",
                "clipSettings",
                "status",
                "progress",
                "outputVideoPath",
                "errorMessage",
                "createdAt",
                "updatedAt",
            ]),
        )
    }

    private func makeJob(
        id: String = "00000000-0000-0000-0000-000000010000",
        status: HighlightJobStatus,
    ) throws -> HighlightJob {
        HighlightJob(
            id: try XCTUnwrap(UUID(uuidString: id)),
            trainingSession: TrainingSession(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000010100")),
                startedAt: Date(timeIntervalSince1970: 2_000),
                endedAt: Date(timeIntervalSince1970: 2_600),
                events: [
                    ShotMarkerEvent(
                        id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000010101")),
                        markedAt: Date(timeIntervalSince1970: 2_120),
                    ),
                ],
            ),
            selectedVideos: [
                HighlightJobVideo(
                    id: "photo-asset-id",
                    recordedStartAt: Date(timeIntervalSince1970: 2_000),
                    duration: 900,
                    source: .photoLibraryAsset(localIdentifier: "photo-asset-id"),
                ),
            ],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
            status: status,
            progress: HighlightJobProgress(completedMarkerCount: 1, totalMarkerCount: 3),
            outputVideoPath: status == .completed ? "HighlightJobs/Outputs/job/highlight.mov" : nil,
            errorMessage: status == .failed ? "导出失败" : nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 3_100),
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobStoreTests
```

Expected: FAIL because `HighlightJob`, `HighlightJobStore`, and related types do not exist.

- [ ] **Step 3: Add the model**

Create `ShotMarker/Models/HighlightJob.swift`:

```swift
import Foundation

struct HighlightJob: Identifiable, Codable, Equatable {
    let id: UUID
    var trainingSession: TrainingSession
    var selectedVideos: [HighlightJobVideo]
    var clipSettings: ClipSettings
    var status: HighlightJobStatus
    var progress: HighlightJobProgress
    var outputVideoPath: String?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    var canCancel: Bool {
        status == .queued || status == .running || status == .saving
    }

    var canRestart: Bool {
        status == .failed || status == .interrupted
    }

    var canClear: Bool {
        status == .completed || status == .failed || status == .interrupted
    }
}

struct HighlightJobVideo: Identifiable, Codable, Equatable {
    let id: String
    let recordedStartAt: Date
    let duration: TimeInterval
    let source: HighlightJobVideoSource

    var selectedTrainingVideo: SelectedTrainingVideo {
        SelectedTrainingVideo(id: id, recordedStartAt: recordedStartAt, duration: duration)
    }
}

enum HighlightJobVideoSource: Codable, Equatable {
    case photoLibraryAsset(localIdentifier: String)
    case jobInputFile(relativePath: String)
}

enum HighlightJobStatus: String, Codable, Equatable {
    case queued
    case running
    case saving
    case completed
    case failed
    case interrupted

    var isLaunchInterruptedState: Bool {
        self == .queued || self == .running || self == .saving
    }
}

struct HighlightJobProgress: Codable, Equatable {
    var completedMarkerCount: Int
    var totalMarkerCount: Int

    static let zero = HighlightJobProgress(completedMarkerCount: 0, totalMarkerCount: 0)

    var fractionCompleted: Double? {
        guard totalMarkerCount > 0 else {
            return nil
        }

        return min(max(Double(completedMarkerCount) / Double(totalMarkerCount), 0), 1)
    }
}
```

- [ ] **Step 4: Add the store**

Create `ShotMarker/Services/HighlightJobStore.swift`:

```swift
import Foundation

protocol HighlightJobStoreProtocol {
    func loadJobs() throws -> [HighlightJob]
    func loadJobsForLaunchRecovery() throws -> [HighlightJob]
    func saveJobs(_ jobs: [HighlightJob]) throws
}

final class HighlightJobStore: HighlightJobStoreProtocol {
    private let fileURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadJobs() throws -> [HighlightJob] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([HighlightJob].self, from: data)
    }

    func loadJobsForLaunchRecovery() throws -> [HighlightJob] {
        try loadJobs().map { job in
            guard job.status.isLaunchInterruptedState else {
                return job
            }

            var interruptedJob = job
            interruptedJob.status = .interrupted
            interruptedJob.updatedAt = Date()
            return interruptedJob
        }
    }

    func saveJobs(_ jobs: [HighlightJob]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(jobs)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("ShotMarker", isDirectory: true)
            .appendingPathComponent("highlight-jobs.json")
    }
}

final class InMemoryHighlightJobStore: HighlightJobStoreProtocol {
    private var jobs: [HighlightJob]

    init(jobs: [HighlightJob] = []) {
        self.jobs = jobs
    }

    func loadJobs() throws -> [HighlightJob] {
        jobs
    }

    func loadJobsForLaunchRecovery() throws -> [HighlightJob] {
        jobs.map { job in
            guard job.status.isLaunchInterruptedState else {
                return job
            }

            var interruptedJob = job
            interruptedJob.status = .interrupted
            interruptedJob.updatedAt = Date()
            return interruptedJob
        }
    }

    func saveJobs(_ jobs: [HighlightJob]) throws {
        self.jobs = jobs
    }
}
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobStoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ShotMarker/Models/HighlightJob.swift ShotMarker/Services/HighlightJobStore.swift ShotMarkerTests/HighlightJobStoreTests.swift
git commit -m "feat: 添加集锦任务模型和存储"
```

## Task 2: Durable Job File Store

**Files:**
- Create: `ShotMarker/Services/HighlightJobFileStore.swift`
- Create: `ShotMarkerTests/HighlightJobFileStoreTests.swift`

- [ ] **Step 1: Write the failing file-store tests**

Create `ShotMarkerTests/HighlightJobFileStoreTests.swift`:

```swift
@testable import ShotMarker
import XCTest

final class HighlightJobFileStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testCopyInputVideoStoresFileUnderJobInputDirectory() throws {
        let store = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000020001"))
        let sourceURL = temporaryDirectory.appendingPathComponent("picked-source.mov")
        try Data([1, 2, 3]).write(to: sourceURL)

        let relativePath = try store.copyInputVideo(at: sourceURL, jobID: jobID, videoID: sourceURL.absoluteString)
        let copiedURL = try store.url(forRelativePath: relativePath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))
        XCTAssertEqual(try Data(contentsOf: copiedURL), Data([1, 2, 3]))
        XCTAssertTrue(relativePath.contains("Inputs/\(jobID.uuidString)"))
        XCTAssertEqual(copiedURL.pathExtension, "mov")
    }

    func testMoveOutputVideoStoresFileUnderJobOutputDirectory() throws {
        let store = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000020002"))
        let sourceURL = temporaryDirectory.appendingPathComponent("export.mov")
        try Data([4, 5, 6]).write(to: sourceURL)

        let relativePath = try store.moveOutputVideo(at: sourceURL, jobID: jobID)
        let movedURL = try store.url(forRelativePath: relativePath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path))
        XCTAssertEqual(try Data(contentsOf: movedURL), Data([4, 5, 6]))
        XCTAssertEqual(relativePath, "HighlightJobs/Outputs/\(jobID.uuidString)/highlight.mov")
    }

    func testRemoveOutputKeepsInputForRestart() throws {
        let store = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000020003"))
        let inputSourceURL = temporaryDirectory.appendingPathComponent("input.mov")
        let outputSourceURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: inputSourceURL)
        try Data([2]).write(to: outputSourceURL)
        let inputRelativePath = try store.copyInputVideo(at: inputSourceURL, jobID: jobID, videoID: inputSourceURL.absoluteString)
        let outputRelativePath = try store.moveOutputVideo(at: outputSourceURL, jobID: jobID)

        try store.removeOutput(for: jobID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.url(forRelativePath: inputRelativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(forRelativePath: outputRelativePath).path))
    }

    func testRemoveAllFilesDeletesInputAndOutputForJob() throws {
        let store = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000020004"))
        let inputSourceURL = temporaryDirectory.appendingPathComponent("input.mov")
        let outputSourceURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: inputSourceURL)
        try Data([2]).write(to: outputSourceURL)
        let inputRelativePath = try store.copyInputVideo(at: inputSourceURL, jobID: jobID, videoID: inputSourceURL.absoluteString)
        let outputRelativePath = try store.moveOutputVideo(at: outputSourceURL, jobID: jobID)

        try store.removeAllFiles(for: jobID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(forRelativePath: inputRelativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(forRelativePath: outputRelativePath).path))
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobFileStoreTests
```

Expected: FAIL because `HighlightJobFileStore` does not exist.

- [ ] **Step 3: Add the file store**

Create `ShotMarker/Services/HighlightJobFileStore.swift`:

```swift
import Foundation

protocol HighlightJobFileStoreProtocol {
    func copyInputVideo(at sourceURL: URL, jobID: UUID, videoID: String) throws -> String
    func moveOutputVideo(at sourceURL: URL, jobID: UUID) throws -> String
    func url(forRelativePath relativePath: String) throws -> URL
    func removeOutput(for jobID: UUID) throws
    func removeAllFiles(for jobID: UUID) throws
}

struct HighlightJobFileStore: HighlightJobFileStoreProtocol {
    private let baseDirectoryURL: URL
    private let fileManager: FileManager

    init(baseDirectoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotMarker", isDirectory: true)
    }

    func copyInputVideo(at sourceURL: URL, jobID: UUID, videoID: String) throws -> String {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(Self.safeFileName(from: videoID)).\(fileExtension)"
        let relativePath = "HighlightJobs/Inputs/\(jobID.uuidString)/\(fileName)"
        let destinationURL = try urlForWriting(relativePath: relativePath)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return relativePath
    }

    func moveOutputVideo(at sourceURL: URL, jobID: UUID) throws -> String {
        let relativePath = "HighlightJobs/Outputs/\(jobID.uuidString)/highlight.mov"
        let destinationURL = try urlForWriting(relativePath: relativePath)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return relativePath
    }

    func url(forRelativePath relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("..") else {
            throw HighlightJobFileStoreError.invalidRelativePath
        }

        return baseDirectoryURL.appendingPathComponent(relativePath)
    }

    func removeOutput(for jobID: UUID) throws {
        try removeDirectoryIfExists(baseDirectoryURL.appendingPathComponent("HighlightJobs/Outputs/\(jobID.uuidString)", isDirectory: true))
    }

    func removeAllFiles(for jobID: UUID) throws {
        try removeDirectoryIfExists(baseDirectoryURL.appendingPathComponent("HighlightJobs/Inputs/\(jobID.uuidString)", isDirectory: true))
        try removeDirectoryIfExists(baseDirectoryURL.appendingPathComponent("HighlightJobs/Outputs/\(jobID.uuidString)", isDirectory: true))
    }

    private func urlForWriting(relativePath: String) throws -> URL {
        let destinationURL = try url(forRelativePath: relativePath)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return destinationURL
    }

    private func removeDirectoryIfExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    private static func safeFileName(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }
}

enum HighlightJobFileStoreError: LocalizedError, Equatable {
    case invalidRelativePath
    case missingFile

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            "任务文件路径无效。"
        case .missingFile:
            "本地视频文件不存在，请重新生成。"
        }
    }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobFileStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ShotMarker/Services/HighlightJobFileStore.swift ShotMarkerTests/HighlightJobFileStoreTests.swift
git commit -m "feat: 添加集锦任务文件存储"
```

## Task 3: Cancellable Video Export

**Files:**
- Modify: `ShotMarker/Services/VideoClipEditingService.swift`
- Modify: `ShotMarkerTests/VideoClipEditingServiceTests.swift`

- [ ] **Step 1: Add a failing cancellation test**

Append this test inside `VideoClipEditingServiceTests` before the helper methods:

```swift
func testMakeHighlightClipCancelsExportSessionWhenTaskIsCancelled() async throws {
    let sourceURL = temporaryDirectory.appendingPathComponent("highlight-cancel-source.mov")
    try await makeSilentVideo(at: sourceURL, duration: 8)
    let markerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000002601"))
    let exportStarted = XCTestExpectation(description: "export started")
    let exportCancelled = XCTestExpectation(description: "export cancelled")
    let service = VideoClipEditingService(
        exportAsset: { _, _, _ in
            exportStarted.fulfill()
            try await Task.sleep(for: .seconds(10))
        },
        cancelExportSession: { _ in
            exportCancelled.fulfill()
        },
    )
    let segments = [
        HighlightClipSegment(
            markerID: markerID,
            videoID: "video",
            markerAt: Date(timeIntervalSince1970: 1_000),
            start: 1,
            duration: 2,
        ),
    ]

    let task = Task {
        try await service.makeHighlightClip(from: segments) { _ in
            AVURLAsset(url: sourceURL)
        }
    }
    await fulfillment(of: [exportStarted], timeout: 5)

    task.cancel()

    do {
        _ = try await task.value
        XCTFail("Expected cancellation")
    } catch is CancellationError {
        await fulfillment(of: [exportCancelled], timeout: 5)
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/VideoClipEditingServiceTests/testMakeHighlightClipCancelsExportSessionWhenTaskIsCancelled
```

Expected: FAIL because `VideoClipEditingService` does not accept `exportAsset` and `cancelExportSession` dependencies.

- [ ] **Step 3: Add export dependencies and cancellation handler**

In `ShotMarker/Services/VideoClipEditingService.swift`, change the stored properties and initializer to:

```swift
struct VideoClipEditingService {
    private let logger: AppLogging
    private let exportAsset: (AVAssetExportSession, URL, AVFileType) async throws -> Void
    private let cancelExportSession: (AVAssetExportSession) -> Void

    init(
        logger: AppLogging = AppLogger.shared,
        exportAsset: @escaping (AVAssetExportSession, URL, AVFileType) async throws -> Void = { exportSession, outputURL, fileType in
            try await exportSession.export(to: outputURL, as: fileType)
        },
        cancelExportSession: @escaping (AVAssetExportSession) -> Void = { exportSession in
            exportSession.cancelExport()
        },
    ) {
        self.logger = logger
        self.exportAsset = exportAsset
        self.cancelExportSession = cancelExportSession
    }
```

Then replace the existing export call:

```swift
try await exportSession.export(to: outputURL, as: .mov)
```

with:

```swift
try await withTaskCancellationHandler {
    try await exportAsset(exportSession, outputURL, .mov)
    try Task.checkCancellation()
} onCancel: {
    cancelExportSession(exportSession)
}
```

- [ ] **Step 4: Run editing-service tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/VideoClipEditingServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ShotMarker/Services/VideoClipEditingService.swift ShotMarkerTests/VideoClipEditingServiceTests.swift
git commit -m "fix: 支持取消视频导出"
```

## Task 4: Highlight Job Runner

**Files:**
- Create: `ShotMarker/Services/HighlightJobRunner.swift`
- Create: `ShotMarkerTests/HighlightJobRunnerTests.swift`

- [ ] **Step 1: Write runner tests**

Create `ShotMarkerTests/HighlightJobRunnerTests.swift`:

```swift
@testable import ShotMarker
import AVFoundation
import XCTest

final class HighlightJobRunnerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    @MainActor
    func testRunCompletesJobAndReportsProgressAndSavingState() async throws {
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let exportedURL = temporaryDirectory.appendingPathComponent("export.mov")
        try Data([1, 2, 3]).write(to: exportedURL)
        let job = try makeJob(status: .queued)
        var savedVideoURL: URL?
        var observedStatuses: [HighlightJobStatus] = []
        let runner = HighlightJobRunner(
            fileStore: fileStore,
            makeHighlightClip: { _, progressHandler, _ in
                progressHandler(HighlightClipGenerationProgress(completedMarkerCount: 0, totalMarkerCount: 1))
                progressHandler(HighlightClipGenerationProgress(completedMarkerCount: 1, totalMarkerCount: 1))
                return exportedURL
            },
            saveVideo: { url in
                savedVideoURL = url
            },
            assetForJobVideo: { _, _ in
                AVURLAsset(url: URL(fileURLWithPath: "/tmp/unused.mov"))
            },
        )

        let completedJob = try await runner.run(job: job) { updatedJob in
            observedStatuses.append(updatedJob.status)
        }

        XCTAssertEqual(completedJob.status, .completed)
        XCTAssertEqual(completedJob.progress, HighlightJobProgress(completedMarkerCount: 1, totalMarkerCount: 1))
        XCTAssertNotNil(completedJob.outputVideoPath)
        XCTAssertEqual(savedVideoURL, try fileStore.url(forRelativePath: XCTUnwrap(completedJob.outputVideoPath)))
        XCTAssertEqual(observedStatuses, [.running, .running, .running, .saving, .completed])
    }

    @MainActor
    func testRunFailsWhenPlanCannotGenerate() async throws {
        let job = try makeJob(
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
        let runner = HighlightJobRunner(
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            makeHighlightClip: { _, _, _ in
                XCTFail("Should not export without matching markers")
                return URL(fileURLWithPath: "/tmp/unused.mov")
            },
            saveVideo: { _ in
                XCTFail("Should not save without an export")
            },
            assetForJobVideo: { _, _ in
                AVURLAsset(url: URL(fileURLWithPath: "/tmp/unused.mov"))
            },
        )

        let failedJob = try await runner.run(job: job) { _ in }

        XCTAssertEqual(failedJob.status, .failed)
        XCTAssertEqual(failedJob.errorMessage, "所选视频没有覆盖任何打点。")
    }

    @MainActor
    func testRunKeepsLocalOutputWhenPhotosSaveFails() async throws {
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let exportedURL = temporaryDirectory.appendingPathComponent("export.mov")
        try Data([1, 2, 3]).write(to: exportedURL)
        let runner = HighlightJobRunner(
            fileStore: fileStore,
            makeHighlightClip: { _, progressHandler, _ in
                progressHandler(HighlightClipGenerationProgress(completedMarkerCount: 1, totalMarkerCount: 1))
                return exportedURL
            },
            saveVideo: { _ in
                throw VideoClipPhotoLibraryError.accessDenied
            },
            assetForJobVideo: { _, _ in
                AVURLAsset(url: URL(fileURLWithPath: "/tmp/unused.mov"))
            },
        )

        let failedJob = try await runner.run(job: try makeJob(status: .queued)) { _ in }

        XCTAssertEqual(failedJob.status, .failed)
        XCTAssertEqual(failedJob.errorMessage, "视频已生成，但保存到相册失败。")
        XCTAssertNotNil(failedJob.outputVideoPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try fileStore.url(forRelativePath: XCTUnwrap(failedJob.outputVideoPath)).path))
    }

    private func makeJob(
        status: HighlightJobStatus,
        selectedVideos: [HighlightJobVideo]? = nil,
    ) throws -> HighlightJob {
        let marker = ShotMarkerEvent(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000030101")),
            markedAt: Date(timeIntervalSince1970: 2_120),
        )
        return HighlightJob(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000030001")),
            trainingSession: TrainingSession(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000030100")),
                startedAt: Date(timeIntervalSince1970: 2_000),
                endedAt: Date(timeIntervalSince1970: 2_600),
                events: [marker],
            ),
            selectedVideos: selectedVideos ?? [
                HighlightJobVideo(
                    id: "video",
                    recordedStartAt: Date(timeIntervalSince1970: 2_000),
                    duration: 900,
                    source: .photoLibraryAsset(localIdentifier: "video"),
                ),
            ],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
            status: status,
            progress: .zero,
            outputVideoPath: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 3_000),
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobRunnerTests
```

Expected: FAIL because `HighlightJobRunner` does not exist.

- [ ] **Step 3: Add the runner**

Create `ShotMarker/Services/HighlightJobRunner.swift`:

```swift
import AVFoundation
import Foundation
#if os(iOS)
    import Photos
#endif

struct HighlightJobRunner {
    typealias MakeHighlightClip = (
        [HighlightClipSegment],
        @MainActor @escaping (HighlightClipGenerationProgress) -> Void,
        @escaping (HighlightClipAssetRequest) async throws -> AVAsset
    ) async throws -> URL

    private let fileStore: HighlightJobFileStoreProtocol
    private let makeHighlightClip: MakeHighlightClip
    private let saveVideo: (URL) async throws -> Void
    private let assetForJobVideo: (HighlightJobVideo, HighlightClipAssetRequest) async throws -> AVAsset

    init(
        fileStore: HighlightJobFileStoreProtocol = HighlightJobFileStore(),
        makeHighlightClip: @escaping MakeHighlightClip,
        saveVideo: @escaping (URL) async throws -> Void,
        assetForJobVideo: @escaping (HighlightJobVideo, HighlightClipAssetRequest) async throws -> AVAsset,
    ) {
        self.fileStore = fileStore
        self.makeHighlightClip = makeHighlightClip
        self.saveVideo = saveVideo
        self.assetForJobVideo = assetForJobVideo
    }

    @MainActor
    func run(
        job originalJob: HighlightJob,
        onChange: @MainActor (HighlightJob) -> Void,
    ) async throws -> HighlightJob {
        var job = originalJob
        job.status = .running
        job.progress = .zero
        job.errorMessage = nil
        job.updatedAt = Date()
        onChange(job)

        let selectedVideos = job.selectedVideos.map(\.selectedTrainingVideo)
        let plan = VideoClipSegmentPlanner.highlightPlan(
            for: job.trainingSession,
            videos: selectedVideos,
            clipSettings: job.clipSettings,
        )
        guard plan.canGenerate else {
            job.status = .failed
            job.errorMessage = "所选视频没有覆盖任何打点。"
            job.updatedAt = Date()
            onChange(job)
            return job
        }

        let videosByID = Dictionary(uniqueKeysWithValues: job.selectedVideos.map { ($0.id, $0) })

        do {
            try Task.checkCancellation()
            let temporaryOutputURL = try await makeHighlightClip(
                plan.segments,
                { progress in
                    job.progress = HighlightJobProgress(
                        completedMarkerCount: progress.completedMarkerCount,
                        totalMarkerCount: progress.totalMarkerCount,
                    )
                    job.updatedAt = Date()
                    onChange(job)
                },
                { request in
                    guard let video = videosByID[request.videoID] else {
                        throw HighlightJobRunnerError.sourceVideoMissing
                    }

                    return try await assetForJobVideo(video, request)
                },
            )

            let outputRelativePath = try fileStore.moveOutputVideo(at: temporaryOutputURL, jobID: job.id)
            job.outputVideoPath = outputRelativePath
            job.status = .saving
            job.updatedAt = Date()
            onChange(job)

            let outputURL = try fileStore.url(forRelativePath: outputRelativePath)
            do {
                try await saveVideo(outputURL)
            } catch {
                job.status = .failed
                job.errorMessage = "视频已生成，但保存到相册失败。"
                job.updatedAt = Date()
                onChange(job)
                return job
            }

            job.status = .completed
            job.progress = HighlightJobProgress(
                completedMarkerCount: plan.matchedMarkerCount,
                totalMarkerCount: plan.matchedMarkerCount,
            )
            job.updatedAt = Date()
            onChange(job)
            return job
        } catch is CancellationError {
            try? fileStore.removeOutput(for: job.id)
            throw CancellationError()
        } catch {
            try? fileStore.removeOutput(for: job.id)
            job.outputVideoPath = nil
            job.status = .failed
            job.errorMessage = Self.userFacingMessage(for: error)
            job.updatedAt = Date()
            onChange(job)
            return job
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

enum HighlightJobRunnerError: LocalizedError, Equatable {
    case sourceVideoMissing

    var errorDescription: String? {
        switch self {
        case .sourceVideoMissing:
            "找不到任务使用的视频，请重新选择视频。"
        }
    }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobRunnerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ShotMarker/Services/HighlightJobRunner.swift ShotMarkerTests/HighlightJobRunnerTests.swift
git commit -m "feat: 添加集锦任务执行器"
```

## Task 5: Highlight Job Manager

**Files:**
- Create: `ShotMarker/ViewModels/HighlightJobManager.swift`
- Create: `ShotMarkerTests/HighlightJobManagerTests.swift`
- Modify: `ShotMarker/Services/HighlightJobRunner.swift`

- [ ] **Step 1: Write manager tests**

Create `ShotMarkerTests/HighlightJobManagerTests.swift`:

```swift
@testable import ShotMarker
import XCTest

@MainActor
final class HighlightJobManagerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testLoadUsesLaunchRecoveryJobs() throws {
        let store = InMemoryHighlightJobStore(jobs: [try makeJob(status: .running)])
        let manager = HighlightJobManager(
            store: store,
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { _ in .immediateCompleted },
        )

        manager.load()

        XCTAssertEqual(manager.jobs.map(\.status), [.interrupted])
    }

    func testCreateJobCopiesFileVideosAndStartsWhenIdle() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("picked.mov")
        try Data([1, 2, 3]).write(to: sourceURL)
        let store = InMemoryHighlightJobStore()
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let manager = HighlightJobManager(
            store: store,
            fileStore: fileStore,
            runnerFactory: { _ in .immediateCompleted },
        )

        let job = try await manager.createJob(
            session: makeSession(),
            selectedVideos: [
                SelectedTrainingVideo(
                    id: sourceURL.absoluteString,
                    recordedStartAt: Date(timeIntervalSince1970: 2_000),
                    duration: 900,
                ),
            ],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
        )
        await Task.yield()

        XCTAssertEqual(job.selectedVideos.first?.source.isJobInputFile, true)
        XCTAssertEqual(manager.jobs.first?.status, .completed)
        let storedJobs = try store.loadJobs()
        XCTAssertEqual(storedJobs.first?.status, .completed)
    }

    func testCancelRunningJobRemovesItAndPersistsRemoval() async throws {
        let store = InMemoryHighlightJobStore()
        let manager = HighlightJobManager(
            store: store,
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { _ in .suspended },
        )
        let job = try await manager.createJob(
            session: makeSession(),
            selectedVideos: [makeSelectedVideo()],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
        )

        manager.cancel(jobID: job.id)

        XCTAssertTrue(manager.jobs.isEmpty)
        XCTAssertTrue(try store.loadJobs().isEmpty)
    }

    func testRestartInterruptedJobRunsSameJob() async throws {
        let interruptedJob = try makeJob(status: .interrupted)
        let store = InMemoryHighlightJobStore(jobs: [interruptedJob])
        let manager = HighlightJobManager(
            store: store,
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { _ in .immediateCompleted },
        )
        manager.load()

        await manager.restart(jobID: interruptedJob.id)
        await Task.yield()

        XCTAssertEqual(manager.jobs.first?.id, interruptedJob.id)
        XCTAssertEqual(manager.jobs.first?.status, .completed)
    }

    func testClearCompletedJobRemovesFilesAndRecord() throws {
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000040001"))
        let outputURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: outputURL)
        let outputRelativePath = try fileStore.moveOutputVideo(at: outputURL, jobID: jobID)
        var completedJob = try makeJob(id: jobID, status: .completed)
        completedJob.outputVideoPath = outputRelativePath
        let store = InMemoryHighlightJobStore(jobs: [completedJob])
        let manager = HighlightJobManager(store: store, fileStore: fileStore, runnerFactory: { _ in .immediateCompleted })
        manager.load()

        manager.clear(jobID: jobID)

        XCTAssertTrue(manager.jobs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try fileStore.url(forRelativePath: outputRelativePath).path))
    }

    private func makeSession() throws -> TrainingSession {
        TrainingSession(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000040100")),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 2_600),
            events: [
                ShotMarkerEvent(
                    id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000040101")),
                    markedAt: Date(timeIntervalSince1970: 2_120),
                ),
            ],
        )
    }

    private func makeSelectedVideo() -> SelectedTrainingVideo {
        SelectedTrainingVideo(id: "photo-asset-id", recordedStartAt: Date(timeIntervalSince1970: 2_000), duration: 900)
    }

    private func makeJob(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000040001")!,
        status: HighlightJobStatus,
    ) throws -> HighlightJob {
        HighlightJob(
            id: id,
            trainingSession: try makeSession(),
            selectedVideos: [
                HighlightJobVideo(
                    id: "photo-asset-id",
                    recordedStartAt: Date(timeIntervalSince1970: 2_000),
                    duration: 900,
                    source: .photoLibraryAsset(localIdentifier: "photo-asset-id"),
                ),
            ],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
            status: status,
            progress: .zero,
            outputVideoPath: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 3_000),
        )
    }
}

private extension HighlightJobVideoSource {
    var isJobInputFile: Bool {
        if case .jobInputFile = self {
            return true
        }

        return false
    }
}

private extension HighlightJobRunner {
    static let immediateCompleted = HighlightJobRunner(
        makeHighlightClip: { _, _, _ in URL(fileURLWithPath: "/tmp/unused.mov") },
        runOverride: { job, onChange in
            var completed = job
            completed.status = .completed
            onChange(completed)
            return completed
        },
    )

    static let suspended = HighlightJobRunner(
        makeHighlightClip: { _, _, _ in URL(fileURLWithPath: "/tmp/unused.mov") },
        runOverride: { job, onChange in
            var running = job
            running.status = .running
            onChange(running)
            try await Task.sleep(for: .seconds(60))
            return running
        },
    )
}
```

This test intentionally introduces `runOverride`. Add that seam in the implementation so manager tests do not perform video export.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobManagerTests
```

Expected: FAIL because `HighlightJobManager` and `HighlightJobRunner.runOverride` do not exist.

- [ ] **Step 3: Add the manager and runner seam**

In `HighlightJobRunner`, add:

```swift
private let runOverride: (@MainActor (HighlightJob, @MainActor (HighlightJob) -> Void) async throws -> HighlightJob)?
```

Add an initializer overload for tests:

```swift
init(
    makeHighlightClip: @escaping MakeHighlightClip,
    runOverride: @escaping @MainActor (HighlightJob, @MainActor (HighlightJob) -> Void) async throws -> HighlightJob,
) {
    self.fileStore = HighlightJobFileStore()
    self.makeHighlightClip = makeHighlightClip
    self.saveVideo = { _ in }
    self.assetForJobVideo = { _, _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/unused.mov")) }
    self.runOverride = runOverride
}
```

Set `runOverride = nil` in the production runner initializer from Task 4.

At the top of `run`, add:

```swift
if let runOverride {
    return try await runOverride(originalJob, onChange)
}
```

Create `ShotMarker/ViewModels/HighlightJobManager.swift`:

```swift
import Foundation

@MainActor
final class HighlightJobManager: ObservableObject {
    @Published private(set) var jobs: [HighlightJob] = []

    private let store: HighlightJobStoreProtocol
    private let fileStore: HighlightJobFileStoreProtocol
    private let runnerFactory: (HighlightJob) -> HighlightJobRunner
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    init(
        store: HighlightJobStoreProtocol,
        fileStore: HighlightJobFileStoreProtocol,
        runnerFactory: @escaping (HighlightJob) -> HighlightJobRunner,
    ) {
        self.store = store
        self.fileStore = fileStore
        self.runnerFactory = runnerFactory
    }

    func load() {
        do {
            jobs = try store.loadJobsForLaunchRecovery()
            persist()
        } catch {
            jobs = []
        }
    }

    @discardableResult
    func createJob(
        session: TrainingSession,
        selectedVideos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
    ) async throws -> HighlightJob {
        let now = Date()
        let jobID = UUID()
        let jobVideos = try selectedVideos.map { video in
            try makeJobVideo(from: video, jobID: jobID)
        }
        let job = HighlightJob(
            id: jobID,
            trainingSession: session,
            selectedVideos: jobVideos,
            clipSettings: clipSettings,
            status: .queued,
            progress: .zero,
            outputVideoPath: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now,
        )

        jobs.insert(job, at: 0)
        persist()
        startNextQueuedJobIfPossible()
        return job
    }

    func cancel(jobID: UUID) {
        runningTasks[jobID]?.cancel()
        runningTasks[jobID] = nil
        try? fileStore.removeAllFiles(for: jobID)
        jobs.removeAll { $0.id == jobID }
        persist()
        startNextQueuedJobIfPossible()
    }

    func restart(jobID: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }

        try? fileStore.removeOutput(for: jobID)
        jobs[index].status = .queued
        jobs[index].progress = .zero
        jobs[index].outputVideoPath = nil
        jobs[index].errorMessage = nil
        jobs[index].updatedAt = Date()
        persist()
        startNextQueuedJobIfPossible()
    }

    func clear(jobID: UUID) {
        runningTasks[jobID]?.cancel()
        runningTasks[jobID] = nil
        try? fileStore.removeAllFiles(for: jobID)
        jobs.removeAll { $0.id == jobID }
        persist()
        startNextQueuedJobIfPossible()
    }

    func playbackURL(for jobID: UUID) throws -> URL {
        guard let job = jobs.first(where: { $0.id == jobID }),
              let outputVideoPath = job.outputVideoPath
        else {
            throw HighlightJobFileStoreError.missingFile
        }

        let url = try fileStore.url(forRelativePath: outputVideoPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            markJobFailed(jobID: jobID, message: "本地视频文件不存在，请重新生成。")
            throw HighlightJobFileStoreError.missingFile
        }

        return url
    }

    private func makeJobVideo(from video: SelectedTrainingVideo, jobID: UUID) throws -> HighlightJobVideo {
        if let sourceURL = URL(string: video.id), sourceURL.isFileURL {
            let relativePath = try fileStore.copyInputVideo(at: sourceURL, jobID: jobID, videoID: video.id)
            return HighlightJobVideo(
                id: video.id,
                recordedStartAt: video.recordedStartAt,
                duration: video.duration,
                source: .jobInputFile(relativePath: relativePath),
            )
        }

        return HighlightJobVideo(
            id: video.id,
            recordedStartAt: video.recordedStartAt,
            duration: video.duration,
            source: .photoLibraryAsset(localIdentifier: video.id),
        )
    }

    private func startNextQueuedJobIfPossible() {
        guard runningTasks.isEmpty,
              let job = jobs.first(where: { $0.status == .queued })
        else {
            return
        }

        let runner = runnerFactory(job)
        let task = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let finalJob = try await runner.run(job: job) { updatedJob in
                    self.update(updatedJob)
                }
                self.update(finalJob)
            } catch is CancellationError {
                self.jobs.removeAll { $0.id == job.id }
                self.persist()
            } catch {
                self.markJobFailed(jobID: job.id, message: error.localizedDescription)
            }

            self.runningTasks[job.id] = nil
            self.startNextQueuedJobIfPossible()
        }
        runningTasks[job.id] = task
    }

    private func update(_ job: HighlightJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            return
        }

        jobs[index] = job
        persist()
    }

    private func markJobFailed(jobID: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }

        jobs[index].status = .failed
        jobs[index].errorMessage = message
        jobs[index].updatedAt = Date()
        persist()
    }

    private func persist() {
        try? store.saveJobs(jobs)
    }
}
```

- [ ] **Step 4: Run manager and runner tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobManagerTests -only-testing:ShotMarkerTests/HighlightJobRunnerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ShotMarker/ViewModels/HighlightJobManager.swift ShotMarker/Services/HighlightJobRunner.swift ShotMarkerTests/HighlightJobManagerTests.swift ShotMarkerTests/HighlightJobRunnerTests.swift
git commit -m "feat: 添加集锦任务队列管理"
```

## Task 6: Live Job Manager Wiring

**Files:**
- Modify: `ShotMarker/ShotMarkerApp.swift`
- Modify: `ShotMarker/ContentView.swift`
- Modify: `ShotMarker/ViewModels/HighlightJobManager.swift`

- [ ] **Step 1: Add live factory**

Add this factory to `HighlightJobManager`:

```swift
#if os(iOS)
    static func live(logger: AppLogging = AppLogger.shared) -> HighlightJobManager {
        let store = HighlightJobStore()
        let fileStore = HighlightJobFileStore()
        let photoLibraryAssetProvider = PhotoLibraryVideoAssetProvider()
        let photoLibrarySaver = VideoClipPhotoLibrarySaver(logger: logger)
        let editingService = VideoClipEditingService(logger: logger)

        return HighlightJobManager(
            store: store,
            fileStore: fileStore,
            runnerFactory: { _ in
                HighlightJobRunner(
                    fileStore: fileStore,
                    makeHighlightClip: { segments, progressHandler, assetProvider in
                        try await editingService.makeHighlightClip(
                            from: segments,
                            progressHandler: progressHandler,
                            assetProvider,
                        )
                    },
                    saveVideo: { outputURL in
                        try await photoLibrarySaver.saveVideo(at: outputURL)
                    },
                    assetForJobVideo: { jobVideo, request in
                        switch jobVideo.source {
                        case let .photoLibraryAsset(localIdentifier):
                            try await photoLibraryAssetProvider.ensureReadAccess()
                            let asset = try photoLibraryAssetProvider.photoAsset(with: localIdentifier)
                            return try await photoLibraryAssetProvider.requestAVAsset(
                                for: asset,
                                deliveryQuality: request.photoLibraryDeliveryQuality(forSourceDuration: asset.duration),
                            )
                        case let .jobInputFile(relativePath):
                            return AVURLAsset(url: try fileStore.url(forRelativePath: relativePath))
                        }
                    },
                )
            },
        )
    }
#endif
```

At the top of `HighlightJobManager.swift`, add `import AVFoundation` because the live factory creates `AVURLAsset`.

- [ ] **Step 2: Inject the manager from app to content**

In `ShotMarker/ShotMarkerApp.swift`, add:

```swift
#if os(iOS)
    @StateObject private var highlightJobManager: HighlightJobManager
#endif
```

Inside `init`, create and load it:

```swift
#if os(iOS)
    let highlightJobManager = HighlightJobManager.live(logger: logger)
    _highlightJobManager = StateObject(wrappedValue: highlightJobManager)
    highlightJobManager.load()
#endif
```

Update the `ContentView` call:

```swift
ContentView(
    store: store,
    syncService: syncService,
    logger: logger,
    logExportService: logExportService,
    highlightJobManager: highlightJobManager,
)
```

For non-iOS, keep the existing initializer call inside `#else` so Watch builds are not affected.

- [ ] **Step 3: Update ContentView initializer**

In `ShotMarker/ContentView.swift`, add:

```swift
#if os(iOS)
    private let highlightJobManager: HighlightJobManager?
#endif
```

Update init:

```swift
@MainActor
init(
    store: TrainingSessionStoreProtocol,
    syncService: PhoneWatchSyncService? = nil,
    logger: AppLogging = AppLogger.shared,
    logExportService: AppLogExportService? = nil,
    highlightJobManager: HighlightJobManager? = nil,
) {
    self.store = store
    self.syncService = syncService
    self.logger = logger
    self.logExportService = logExportService
    #if os(iOS)
        self.highlightJobManager = highlightJobManager
    #endif
}
```

Pass it to the list view on iOS:

```swift
TrainingSessionListView(
    store: store,
    diagnosticsSnapshotProvider: syncService?.diagnosticsSnapshot,
    logger: logger,
    logExportService: logExportService,
    highlightJobManager: highlightJobManager,
)
```

- [ ] **Step 4: Build the iOS scheme**

Run:

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ShotMarker/ShotMarkerApp.swift ShotMarker/ContentView.swift ShotMarker/ViewModels/HighlightJobManager.swift
git commit -m "feat: 接入集锦任务管理器"
```

## Task 7: Home-Screen Job Row View Data And Section

**Files:**
- Create: `ShotMarker/ViewModels/HighlightJobRowViewData.swift`
- Create: `ShotMarker/Views/HighlightJobListSection.swift`
- Create: `ShotMarkerTests/HighlightJobRowViewDataTests.swift`
- Modify: `ShotMarker/Views/TrainingSessionListView.swift`

- [ ] **Step 1: Write row view data tests**

Create `ShotMarkerTests/HighlightJobRowViewDataTests.swift`:

```swift
@testable import ShotMarker
import XCTest

final class HighlightJobRowViewDataTests: XCTestCase {
    func testRunningJobShowsProgressAndCancelAction() throws {
        let row = HighlightJobRowViewData(job: try makeJob(status: .running, progress: HighlightJobProgress(completedMarkerCount: 3, totalMarkerCount: 10)))

        XCTAssertEqual(row.statusText, "正在生成 3/10")
        XCTAssertEqual(row.progressFraction, 0.3)
        XCTAssertTrue(row.showsCancel)
        XCTAssertFalse(row.showsRestart)
        XCTAssertFalse(row.showsPlay)
    }

    func testCompletedJobShowsPlayAndClearActions() throws {
        let row = HighlightJobRowViewData(job: try makeJob(status: .completed))

        XCTAssertEqual(row.statusText, "已完成")
        XCTAssertNil(row.progressFraction)
        XCTAssertTrue(row.showsPlay)
        XCTAssertTrue(row.showsClear)
    }

    func testInterruptedJobShowsRestartAndClearActions() throws {
        let row = HighlightJobRowViewData(job: try makeJob(status: .interrupted))

        XCTAssertEqual(row.statusText, "已中断，可重新开始")
        XCTAssertTrue(row.showsRestart)
        XCTAssertTrue(row.showsClear)
    }

    func testFailedJobShowsErrorMessage() throws {
        var job = try makeJob(status: .failed)
        job.errorMessage = "视频已生成，但保存到相册失败。"

        let row = HighlightJobRowViewData(job: job)

        XCTAssertEqual(row.statusText, "视频已生成，但保存到相册失败。")
        XCTAssertTrue(row.showsRestart)
        XCTAssertTrue(row.showsClear)
    }

    private func makeJob(
        status: HighlightJobStatus,
        progress: HighlightJobProgress = .zero,
    ) throws -> HighlightJob {
        HighlightJob(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000050001")),
            trainingSession: TrainingSession(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000050100")),
                startedAt: Date(timeIntervalSince1970: 2_000),
                endedAt: Date(timeIntervalSince1970: 2_600),
                events: [],
            ),
            selectedVideos: [],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
            status: status,
            progress: progress,
            outputVideoPath: status == .completed ? "HighlightJobs/Outputs/job/highlight.mov" : nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 3_000),
        )
    }
}
```

- [ ] **Step 2: Run focused test and verify it fails**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobRowViewDataTests
```

Expected: FAIL because `HighlightJobRowViewData` does not exist.

- [ ] **Step 3: Add row view data**

Create `ShotMarker/ViewModels/HighlightJobRowViewData.swift`:

```swift
import Foundation

struct HighlightJobRowViewData: Identifiable, Equatable {
    let id: UUID
    let title: String
    let statusText: String
    let progressFraction: Double?
    let showsCancel: Bool
    let showsRestart: Bool
    let showsPlay: Bool
    let showsClear: Bool

    init(job: HighlightJob) {
        id = job.id
        title = job.trainingSession.markerTimeRange.startedAt.formatted(.dateTime.month().day().hour().minute())
        statusText = Self.statusText(for: job)
        progressFraction = job.status == .running || job.status == .queued ? job.progress.fractionCompleted : nil
        showsCancel = job.status == .queued || job.status == .running || job.status == .saving
        showsRestart = job.status == .failed || job.status == .interrupted
        showsPlay = job.status == .completed
        showsClear = job.status == .completed || job.status == .failed || job.status == .interrupted
    }

    private static func statusText(for job: HighlightJob) -> String {
        switch job.status {
        case .queued:
            "等待中"
        case .running:
            if job.progress.totalMarkerCount > 0 {
                "正在生成 \(job.progress.completedMarkerCount)/\(job.progress.totalMarkerCount)"
            } else {
                "正在生成"
            }
        case .saving:
            "正在保存到相册"
        case .completed:
            "已完成"
        case .failed:
            job.errorMessage ?? "集锦生成失败"
        case .interrupted:
            "已中断，可重新开始"
        }
    }
}
```

- [ ] **Step 4: Add the SwiftUI section**

Create `ShotMarker/Views/HighlightJobListSection.swift`:

```swift
import SwiftUI

struct HighlightJobListSection: View {
    let jobs: [HighlightJob]
    let onCancel: (UUID) -> Void
    let onRestart: (UUID) -> Void
    let onPlay: (UUID) -> Void
    let onClear: (UUID) -> Void

    var body: some View {
        if !jobs.isEmpty {
            Section("集锦任务") {
                ForEach(jobs) { job in
                    row(HighlightJobRowViewData(job: job))
                }
            }
        }
    }

    private func row(_ row: HighlightJobRowViewData) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.headline)
                Text(row.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let progressFraction = row.progressFraction {
                    ProgressView(value: progressFraction)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if row.showsPlay {
                    iconButton("播放集锦", systemImage: "play.circle") {
                        onPlay(row.id)
                    }
                }

                if row.showsRestart {
                    iconButton("重新开始", systemImage: "arrow.clockwise") {
                        onRestart(row.id)
                    }
                }

                if row.showsCancel {
                    iconButton("取消任务", systemImage: "xmark.circle.fill") {
                        onCancel(row.id)
                    }
                }

                if row.showsClear {
                    iconButton("清理任务", systemImage: "trash") {
                        onClear(row.id)
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func iconButton(
        _ accessibilityLabel: String,
        systemImage: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
```

- [ ] **Step 5: Wire section into TrainingSessionListView**

In `ShotMarker/Views/TrainingSessionListView.swift`, add:

```swift
#if os(iOS)
    @ObservedObject private var highlightJobManager: HighlightJobManager
#endif
```

Update both initializers to accept `highlightJobManager: HighlightJobManager? = nil`. For iOS, assign:

```swift
#if os(iOS)
    _highlightJobManager = ObservedObject(wrappedValue: highlightJobManager ?? HighlightJobManager.live(logger: logger))
#endif
```

In `content`, wrap the rows in a single `List` that starts with the job section:

```swift
List {
    #if os(iOS)
        HighlightJobListSection(
            jobs: highlightJobManager.jobs,
            onCancel: { highlightJobManager.cancel(jobID: $0) },
            onRestart: { jobID in Task { await highlightJobManager.restart(jobID: jobID) } },
            onPlay: { jobID in playHighlightJob(jobID) },
            onClear: { highlightJobManager.clear(jobID: $0) },
        )
    #endif

    ForEach(viewModel.rows) { row in
        if viewModel.isSelectionMode {
            TrainingSessionRow(
                row: row,
                isSelectionMode: true,
                isSelected: viewModel.isSelected(row.id),
            )
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.toggleSelection(for: row.id)
            }
            .listRowBackground(viewModel.isSelected(row.id) ? Color.accentColor.opacity(0.12) : Color.clear)
        } else {
            trainingSessionNavigationRow(for: row)
        }
    }
}
```

Keep the existing `ContentUnavailableView` for error and empty states. In the empty state, still show `HighlightJobListSection` above the unavailable view if jobs exist by using a `List` with the section and a plain row containing the unavailable view.

- [ ] **Step 6: Run row tests and build**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobRowViewDataTests
```

Expected: PASS.

Run:

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ShotMarker/ViewModels/HighlightJobRowViewData.swift ShotMarker/Views/HighlightJobListSection.swift ShotMarker/Views/TrainingSessionListView.swift ShotMarkerTests/HighlightJobRowViewDataTests.swift
git commit -m "feat: 在首页展示集锦任务列表"
```

## Task 8: Completed Video Playback

**Files:**
- Create: `ShotMarker/Views/HighlightJobVideoPlayerView.swift`
- Modify: `ShotMarker/Views/TrainingSessionListView.swift`

- [ ] **Step 1: Add player view**

Create `ShotMarker/Views/HighlightJobVideoPlayerView.swift`:

```swift
#if os(iOS)
    import AVKit
    import SwiftUI

    struct HighlightJobVideoPlayerView: UIViewControllerRepresentable {
        let videoURL: URL

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = AVPlayer(url: videoURL)
            return controller
        }

        func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
            if (uiViewController.player?.currentItem?.asset as? AVURLAsset)?.url != videoURL {
                uiViewController.player = AVPlayer(url: videoURL)
            }
        }
    }
#endif
```

- [ ] **Step 2: Present playback sheet from TrainingSessionListView**

In `TrainingSessionListView`, add state:

```swift
#if os(iOS)
    @State private var highlightPlaybackURL: URL?
    @State private var highlightPlaybackErrorMessage: String?
#endif
```

Add sheet and alert to `body` modifiers:

```swift
#if os(iOS)
    .sheet(isPresented: highlightPlaybackSheetBinding) {
        if let highlightPlaybackURL {
            HighlightJobVideoPlayerView(videoURL: highlightPlaybackURL)
        }
    }
    .alert("无法打开集锦", isPresented: highlightPlaybackErrorBinding) {
        Button("好", role: .cancel) {
            highlightPlaybackErrorMessage = nil
        }
    } message: {
        Text(highlightPlaybackErrorMessage ?? "未知错误")
    }
#endif
```

Add helpers:

```swift
#if os(iOS)
    private var highlightPlaybackSheetBinding: Binding<Bool> {
        Binding(
            get: { highlightPlaybackURL != nil },
            set: { isPresented in
                if !isPresented {
                    highlightPlaybackURL = nil
                }
            },
        )
    }

    private var highlightPlaybackErrorBinding: Binding<Bool> {
        Binding(
            get: { highlightPlaybackErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    highlightPlaybackErrorMessage = nil
                }
            },
        )
    }

    @MainActor
    private func playHighlightJob(_ jobID: UUID) {
        do {
            highlightPlaybackURL = try highlightJobManager.playbackURL(for: jobID)
        } catch {
            highlightPlaybackErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
#endif
```

- [ ] **Step 3: Build the iOS scheme**

Run:

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add ShotMarker/Views/HighlightJobVideoPlayerView.swift ShotMarker/Views/TrainingSessionListView.swift
git commit -m "feat: 支持播放已完成集锦任务"
```

## Task 9: Create Jobs From Highlight Page

**Files:**
- Modify: `ShotMarker/Views/TrainingSessionHighlightView.swift`
- Modify: `ShotMarker/Views/TrainingSessionListView.swift`

- [ ] **Step 1: Inject job manager into destination**

In `TrainingSessionListView.destination(for:)`, pass the manager:

```swift
TrainingSessionHighlightView(
    session: session,
    highlightJobManager: highlightJobManager,
)
```

- [ ] **Step 2: Update highlight view initializer**

In `TrainingSessionHighlightView`, add:

```swift
@Environment(\.dismiss) private var dismiss
private let highlightJobManager: HighlightJobManager?
@State private var isCreatingHighlightJob = false
```

Update init:

```swift
init(
    session: TrainingSession,
    logger: AppLogging = AppLogger.shared,
    highlightJobManager: HighlightJobManager? = nil,
) {
    self.session = session
    self.logger = logger
    self.highlightJobManager = highlightJobManager
    ...
}
```

- [ ] **Step 3: Replace in-page generation button action**

In `generateHighlightSection`, replace:

```swift
Task {
    await generateHighlight()
}
```

with:

```swift
Task {
    await createHighlightJob()
}
```

Change button label and disabled state to use `isCreatingHighlightJob`:

```swift
if isCreatingHighlightJob {
    ProgressView()
}

Text(isCreatingHighlightJob ? "创建中" : "生成集锦")
    .frame(maxWidth: .infinity)
```

Disable when:

```swift
.disabled(!plan.canGenerate || isLoadingVideos || isCreatingHighlightJob)
```

Remove the page-level generation progress UI from this section, or leave it unreachable only until `generateHighlight()` is removed. The final UI should not show `generationProgress` inside this page.

- [ ] **Step 4: Add createHighlightJob**

Add:

```swift
@MainActor
private func createHighlightJob() async {
    let currentPlan = plan
    guard currentPlan.canGenerate else {
        return
    }

    guard let highlightJobManager else {
        alert = HighlightFlowAlert(title: "无法创建任务", message: "集锦任务管理器不可用。")
        return
    }

    logger.info(
        "highlight.job.create.started",
        category: .video,
        message: "开始创建集锦任务",
        context: highlightPlanContext(currentPlan, extra: [
            "segmentCount": "\(currentPlan.segments.count)",
            "secondsBeforeMarker": Self.secondsString(clipSettings.secondsBeforeMarker),
            "secondsAfterMarker": Self.secondsString(clipSettings.secondsAfterMarker),
        ]),
    )

    isCreatingHighlightJob = true
    defer {
        isCreatingHighlightJob = false
    }

    do {
        _ = try await highlightJobManager.createJob(
            session: session,
            selectedVideos: selectedVideos,
            clipSettings: clipSettings,
        )
        cleanupTemporaryVideos()
        selectedItems = []
        selectedVideos = []
        selectedVideoItems = []
        logger.info(
            "highlight.job.create.succeeded",
            category: .video,
            message: "集锦任务创建成功",
            context: highlightPlanContext(currentPlan),
        )
        dismiss()
    } catch {
        logger.error(
            "highlight.job.create.failed",
            category: .video,
            message: "集锦任务创建失败",
            error: error,
            context: highlightPlanContext(currentPlan),
        )
        alert = HighlightFlowAlert(
            title: "创建任务失败",
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
        )
    }
}
```

Delete the old `generateHighlight()` method and remove `isGenerating` / `generationProgress` state if no other code uses them. Update toolbar and `.onDisappear` conditions that referenced `isGenerating`:

```swift
.disabled(isCreatingHighlightJob || isExportingTrainingSession)
```

and:

```swift
.onDisappear {
    cancelPreparationTasks()
    cleanupTemporaryVideos()
}
```

This is safe because durable file inputs are copied before dismissing.

- [ ] **Step 5: Build and run focused existing tests**

Run:

```bash
xcodebuild build -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS.

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/TrainingVideoLoadingServiceTests -only-testing:ShotMarkerTests/VideoClipSegmentPlannerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ShotMarker/Views/TrainingSessionHighlightView.swift ShotMarker/Views/TrainingSessionListView.swift
git commit -m "feat: 从集锦页面创建后台任务"
```

## Task 10: Queue Behavior Polish And Logging

**Files:**
- Modify: `ShotMarker/ViewModels/HighlightJobManager.swift`
- Modify: `ShotMarker/Services/HighlightJobRunner.swift`
- Modify: `ShotMarker/Views/HighlightJobListSection.swift`

- [ ] **Step 1: Add queue lifecycle logs**

Add `logger: AppLogging` to `HighlightJobManager`, defaulting to `AppLogger.shared`, and log:

```swift
logger.info("highlight.job.queued", category: .video, message: "集锦任务已加入队列", context: ["jobID": job.id.uuidString])
logger.info("highlight.job.cancelled", category: .video, message: "集锦任务已取消", context: ["jobID": jobID.uuidString])
logger.info("highlight.job.restarted", category: .video, message: "集锦任务重新开始", context: ["jobID": jobID.uuidString])
logger.info("highlight.job.cleared", category: .video, message: "集锦任务已清理", context: ["jobID": jobID.uuidString])
```

Pass logger through `HighlightJobManager.live(logger:)`.

- [ ] **Step 2: Make cancel affordance clear**

In `HighlightJobListSection`, apply destructive tint to cancel and clear buttons:

```swift
.foregroundStyle(systemImage == "xmark.circle.fill" || systemImage == "trash" ? Color.red : Color.accentColor)
```

Keep the button labels icon-only with accessibility labels.

- [ ] **Step 3: Run relevant tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ShotMarkerTests/HighlightJobManagerTests -only-testing:ShotMarkerTests/AppLoggerTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add ShotMarker/ViewModels/HighlightJobManager.swift ShotMarker/Services/HighlightJobRunner.swift ShotMarker/Views/HighlightJobListSection.swift
git commit -m "feat: 完善集锦任务队列反馈"
```

## Task 11: Full Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full iPhone tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarker -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS.

- [ ] **Step 2: Run Watch tests**

Run:

```bash
xcodebuild test -project ShotMarker.xcodeproj -scheme ShotMarkerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'
```

Expected: PASS. This verifies the iOS-only job queue did not break shared model compilation or Watch sync tests.

- [ ] **Step 3: Manual simulator checks**

Run the app on the iPhone simulator and verify:

1. Select a training session, choose a usable video, tap “生成集锦”.
2. App returns to home.
3. “集锦任务” appears above training rows.
4. Running task shows progress and a cancel button.
5. Cancel removes the task.
6. Create another task and let it finish.
7. Completed task stays in the list.
8. Play button opens the system video player.
9. Clear button removes the completed task and local file.
10. Start a task, terminate the app from the switcher, relaunch, and confirm the task shows “已中断，可重新开始”.
11. Tap restart and confirm it can run again.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short
```

Expected: clean, or only intentional uncommitted verification artifacts that should be removed before completion.

## Self-Review Checklist

- Spec coverage:
  - Persistent task list: Tasks 1, 5, 6.
  - Durable local inputs/outputs: Task 2.
  - Serial background-capable execution: Tasks 4, 5.
  - Cancellable export: Task 3.
  - Home-screen progress, cancel, restart, play, clear: Tasks 7, 8.
  - Create task from highlight page and return home: Task 9.
  - Interrupted restart semantics: Tasks 1, 5, 11.
  - No training-session clipping state: no task modifies `TrainingSession`.
- Placeholder scan:
  - No step depends on unspecified file names or unnamed tests.
  - Every new type has an explicit file and core API.
- Type consistency:
  - `HighlightJobStatus`, `HighlightJobProgress`, `HighlightJobVideoSource`, and manager method names match across tasks.
  - Manager uses `createJob(session:selectedVideos:clipSettings:)`; temporary-video durability comes from `SelectedTrainingVideo.id` file URLs already produced by the current selection flow.

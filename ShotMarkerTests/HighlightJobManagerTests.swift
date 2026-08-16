@testable import ShotMarker
import AVFoundation
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
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightJobManager(
            store: store,
            fileStore: fileStore,
            runnerFactory: { _ in .immediateCompleted },
            analytics: analytics,
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
        XCTAssertEqual(analytics.events, [.highlightGenerateSucceeded])
    }

    func testFailedHighlightGenerationDoesNotTrackSuccess() async throws {
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightJobManager(
            store: InMemoryHighlightJobStore(),
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { _ in .immediateFailed },
            analytics: analytics,
        )

        _ = try await manager.createJob(
            session: makeSession(),
            selectedVideos: [makeSelectedVideo()],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
        )
        await Task.yield()

        XCTAssertEqual(manager.jobs.first?.status, .failed)
        XCTAssertTrue(analytics.events.isEmpty)
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

    func testSaveCompletedJobToPhotoLibraryMarksItSaved() async throws {
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000040001"))
        let outputURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: outputURL)
        let outputRelativePath = try fileStore.moveOutputVideo(at: outputURL, jobID: jobID)
        var completedJob = try makeJob(id: jobID, status: .completed)
        completedJob.outputVideoPath = outputRelativePath
        let store = InMemoryHighlightJobStore(jobs: [completedJob])
        var savedURL: URL?
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightJobManager(
            store: store,
            fileStore: fileStore,
            runnerFactory: { _ in .immediateCompleted },
            saveVideoToPhotoLibrary: { url in
                savedURL = url
            },
            analytics: analytics,
        )
        manager.load()

        await manager.saveToPhotoLibrary(jobID: jobID)

        XCTAssertEqual(savedURL, try fileStore.url(forRelativePath: outputRelativePath))
        XCTAssertEqual(manager.jobs.first?.status, .completed)
        XCTAssertNotNil(manager.jobs.first?.photoLibrarySavedAt)
        XCTAssertNil(manager.jobs.first?.photoLibrarySaveErrorMessage)
        XCTAssertNotNil(try store.loadJobs().first?.photoLibrarySavedAt)
        XCTAssertEqual(analytics.events, [.highlightSaveSucceeded])
    }

    func testSaveAlreadySavedCompletedJobSavesAgainAndRefreshesSavedAt() async throws {
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000040001"))
        let outputURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: outputURL)
        let outputRelativePath = try fileStore.moveOutputVideo(at: outputURL, jobID: jobID)
        let previousSavedAt = Date(timeIntervalSince1970: 4_000)
        var completedJob = try makeJob(id: jobID, status: .completed)
        completedJob.outputVideoPath = outputRelativePath
        completedJob.photoLibrarySavedAt = previousSavedAt
        let store = InMemoryHighlightJobStore(jobs: [completedJob])
        var savedURLs: [URL] = []
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightJobManager(
            store: store,
            fileStore: fileStore,
            runnerFactory: { _ in .immediateCompleted },
            saveVideoToPhotoLibrary: { url in
                savedURLs.append(url)
            },
            analytics: analytics,
        )
        manager.load()

        await manager.saveToPhotoLibrary(jobID: jobID)

        XCTAssertEqual(savedURLs, [try fileStore.url(forRelativePath: outputRelativePath)])
        XCTAssertGreaterThan(try XCTUnwrap(manager.jobs.first?.photoLibrarySavedAt), previousSavedAt)
        XCTAssertGreaterThan(try XCTUnwrap(try store.loadJobs().first?.photoLibrarySavedAt), previousSavedAt)
        XCTAssertEqual(analytics.events, [.highlightSaveSucceeded])
    }

    func testSaveCompletedJobToPhotoLibraryFailureLeavesJobCompletedAndRetryable() async throws {
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000040001"))
        let outputURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: outputURL)
        let outputRelativePath = try fileStore.moveOutputVideo(at: outputURL, jobID: jobID)
        var completedJob = try makeJob(id: jobID, status: .completed)
        completedJob.outputVideoPath = outputRelativePath
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightJobManager(
            store: InMemoryHighlightJobStore(jobs: [completedJob]),
            fileStore: fileStore,
            runnerFactory: { _ in .immediateCompleted },
            saveVideoToPhotoLibrary: { _ in
                throw VideoClipPhotoLibraryError.accessDenied
            },
            analytics: analytics,
        )
        manager.load()

        await manager.saveToPhotoLibrary(jobID: jobID)

        XCTAssertEqual(manager.jobs.first?.status, .completed)
        XCTAssertNil(manager.jobs.first?.photoLibrarySavedAt)
        XCTAssertEqual(manager.jobs.first?.photoLibrarySaveErrorMessage, "没有相册保存权限。请允许 ShotMarker 添加照片后再试。")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try fileStore.url(forRelativePath: outputRelativePath).path))
        XCTAssertTrue(analytics.events.isEmpty)
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

    static let immediateFailed = HighlightJobRunner(
        makeHighlightClip: { _, _, _ in URL(fileURLWithPath: "/tmp/unused.mov") },
        runOverride: { _, _ in
            throw HighlightJobRunnerTestError.failed
        },
    )
}

private enum HighlightJobRunnerTestError: Error {
    case failed
}

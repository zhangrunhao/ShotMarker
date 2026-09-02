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
            confirmedSegments: makeConfirmedSegments(videoID: sourceURL.absoluteString),
        )
        await Task.yield()

        XCTAssertEqual(job.selectedVideos.first?.source.isJobInputFile, true)
        XCTAssertEqual(manager.jobs.first?.status, .completed)
        let storedJobs = try store.loadJobs()
        XCTAssertEqual(storedJobs.first?.status, .completed)
        XCTAssertEqual(analytics.events, [.highlightGenerateSucceeded])
    }

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
                id: UUID(),
                videoID: sourceURL.absoluteString,
                markerIDs: [],
                start: 0,
                duration: 1,
                markerNumberLowerBound: 1,
                markerNumberUpperBound: 1,
                markerTotalCount: 1,
            ),
        ]

        do {
            _ = try await manager.createJob(
                session: makeSession(),
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

    func testCreateJobKeepsCapturedStyleAfterDefaultsChange() async throws {
        let suiteName = "ShotMarker.HighlightJobManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = ClipSettingsStore(userDefaults: defaults)
        let capturedStyle = MarkerLabelStyle(
            fontSizeRatio: 0.14,
            normalizedCenterX: 0.8,
            normalizedCenterY: 0.3,
            textOpacity: 0.7,
            backgroundOpacity: 0.2,
        )
        let manager = HighlightJobManager(
            store: InMemoryHighlightJobStore(),
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { _ in .immediateCompleted },
        )

        let job = try await manager.createJob(
            session: makeSession(),
            selectedVideos: [makeSelectedVideo()],
            clipSettings: ClipSettings(
                secondsBeforeMarker: 9,
                secondsAfterMarker: 4,
                markerLabelStyle: capturedStyle,
            ),
            confirmedSegments: makeConfirmedSegments(),
        )
        settingsStore.save(
            ClipSettings(
                secondsBeforeMarker: 9,
                secondsAfterMarker: 4,
                markerLabelStyle: .default,
            ),
        )

        XCTAssertEqual(job.clipSettings.markerLabelStyle, capturedStyle)
        XCTAssertEqual(manager.jobs.first?.clipSettings.markerLabelStyle, capturedStyle)
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
            confirmedSegments: makeConfirmedSegments(),
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
            confirmedSegments: makeConfirmedSegments(),
        )

        manager.cancel(jobID: job.id)

        XCTAssertTrue(manager.jobs.isEmpty)
        XCTAssertTrue(try store.loadJobs().isEmpty)
    }

    func testCancelSuppressesCompletedResultFromNonCooperativeRunner() async throws {
        let gate = NonCooperativeRunnerGate()
        let taskSettled = expectation(description: "cancelled generation task settled")
        taskSettled.assertForOverFulfill = true
        let settlementProbe = TaskSettlementProbe(expectation: taskSettled)
        let store = SettlementHighlightJobStore()
        let analytics = SettlementAnalyticsTracker(settlementProbe: settlementProbe)
        let manager = HighlightJobManager(
            store: store,
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { _ in
                HighlightJobRunner(
                    makeHighlightClip: { _, _, _, _ in
                        URL(fileURLWithPath: "/tmp/unused.mov")
                    },
                    runOverride: { job, onChange in
                        var running = job
                        running.status = .running
                        onChange(running)
                        await gate.suspendUntilReleased()

                        var completed = running
                        completed.status = .completed
                        return completed
                    },
                )
            },
            analytics: analytics,
        )
        let job = try await manager.createJob(
            session: makeSession(),
            selectedVideos: [makeSelectedVideo()],
            clipSettings: ClipSettings(secondsBeforeMarker: 9, secondsAfterMarker: 4),
            confirmedSegments: makeConfirmedSegments(),
        )
        await gate.waitUntilStarted()

        manager.cancel(jobID: job.id)
        store.signalOnNextSave(settlementProbe.signal)
        await gate.release()
        await fulfillment(of: [taskSettled], timeout: 1)

        XCTAssertTrue(manager.jobs.isEmpty)
        XCTAssertTrue(try store.loadJobs().isEmpty)
        XCTAssertTrue(analytics.events.isEmpty)
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

    func testRestartUsesPersistedMarkerStyle() async throws {
        let style = MarkerLabelStyle(
            fontSizeRatio: 0.16,
            normalizedCenterX: 0.25,
            normalizedCenterY: 0.75,
            textOpacity: 0.55,
            backgroundOpacity: 0.45,
        )
        let interruptedJob = try makeJob(status: .interrupted, markerLabelStyle: style)
        var runnerStyle: MarkerLabelStyle?
        let manager = HighlightJobManager(
            store: InMemoryHighlightJobStore(jobs: [interruptedJob]),
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { job in
                runnerStyle = job.clipSettings.markerLabelStyle
                return .immediateCompleted
            },
        )
        manager.load()

        await manager.restart(jobID: interruptedJob.id)
        await Task.yield()

        XCTAssertEqual(runnerStyle, style)
    }

    func testRestartAndLaunchRecoveryKeepVersionOneSnapshot() async throws {
        let segments = makeConfirmedSegments()
        var interruptedJob = try makeJob(status: .interrupted)
        interruptedJob.clipPlanVersion = 1
        interruptedJob.confirmedSegments = segments
        var runnerJob: HighlightJob?
        let manager = HighlightJobManager(
            store: InMemoryHighlightJobStore(jobs: [interruptedJob]),
            fileStore: HighlightJobFileStore(baseDirectoryURL: temporaryDirectory),
            runnerFactory: { job in
                runnerJob = job
                return .immediateCompleted
            },
        )
        manager.load()

        await manager.restart(jobID: interruptedJob.id)
        await Task.yield()

        XCTAssertEqual(runnerJob?.clipPlanVersion, 1)
        XCTAssertEqual(runnerJob?.confirmedSegments, segments)
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

    func testPhotoLibrarySaveDoesNotTrackWhenFinalJobPersistenceFails() async throws {
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let jobID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000040001"))
        let outputURL = temporaryDirectory.appendingPathComponent("output.mov")
        try Data([1]).write(to: outputURL)
        let outputRelativePath = try fileStore.moveOutputVideo(at: outputURL, jobID: jobID)
        var completedJob = try makeJob(id: jobID, status: .completed)
        completedJob.outputVideoPath = outputRelativePath
        let store = FailingSaveHighlightJobStore(
            jobs: [completedJob],
            failingSaveCall: 3,
        )
        let analytics = SpyAnalyticsTracker()
        var didSaveVideo = false
        let manager = HighlightJobManager(
            store: store,
            fileStore: fileStore,
            runnerFactory: { _ in .immediateCompleted },
            saveVideoToPhotoLibrary: { _ in
                didSaveVideo = true
            },
            analytics: analytics,
        )
        manager.load()

        await manager.saveToPhotoLibrary(jobID: jobID)

        XCTAssertTrue(didSaveVideo)
        XCTAssertEqual(store.saveCallCount, 3)
        XCTAssertNil(try store.loadJobs().first?.photoLibrarySavedAt)
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

    private func makeJob(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000040001")!,
        status: HighlightJobStatus,
        markerLabelStyle: MarkerLabelStyle = .default,
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
            clipSettings: ClipSettings(
                secondsBeforeMarker: 9,
                secondsAfterMarker: 4,
                markerLabelStyle: markerLabelStyle,
            ),
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
        makeHighlightClip: { _, _, _, _ in URL(fileURLWithPath: "/tmp/unused.mov") },
        runOverride: { job, onChange in
            var completed = job
            completed.status = .completed
            onChange(completed)
            return completed
        },
    )

    static let suspended = HighlightJobRunner(
        makeHighlightClip: { _, _, _, _ in URL(fileURLWithPath: "/tmp/unused.mov") },
        runOverride: { job, onChange in
            var running = job
            running.status = .running
            onChange(running)
            try await Task.sleep(for: .seconds(60))
            return running
        },
    )

    static let immediateFailed = HighlightJobRunner(
        makeHighlightClip: { _, _, _, _ in URL(fileURLWithPath: "/tmp/unused.mov") },
        runOverride: { _, _ in
            throw HighlightJobRunnerTestError.failed
        },
    )
}

private enum HighlightJobRunnerTestError: Error {
    case failed
}

private final class FailingSaveHighlightJobStore: HighlightJobStoreProtocol {
    private var jobs: [HighlightJob]
    private let failingSaveCall: Int
    private(set) var saveCallCount = 0

    init(jobs: [HighlightJob], failingSaveCall: Int) {
        self.jobs = jobs
        self.failingSaveCall = failingSaveCall
    }

    func loadJobs() throws -> [HighlightJob] {
        jobs
    }

    func loadJobsForLaunchRecovery() throws -> [HighlightJob] {
        jobs
    }

    func saveJobs(_ jobs: [HighlightJob]) throws {
        saveCallCount += 1
        if saveCallCount == failingSaveCall {
            throw FailingSaveHighlightJobStoreError.failed
        }
        self.jobs = jobs
    }
}

private enum FailingSaveHighlightJobStoreError: Error {
    case failed
}

private actor NonCooperativeRunnerGate {
    private var didStart = false
    private var didRelease = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        guard !didStart else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func suspendUntilReleased() async {
        didStart = true
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }

        guard !didRelease else {
            return
        }

        await withCheckedContinuation { continuation in
            if didRelease {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    func release() {
        didRelease = true
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}

private final class SettlementHighlightJobStore: HighlightJobStoreProtocol {
    private var jobs: [HighlightJob] = []
    private var onNextSave: (() -> Void)?

    func loadJobs() throws -> [HighlightJob] {
        jobs
    }

    func loadJobsForLaunchRecovery() throws -> [HighlightJob] {
        jobs
    }

    func saveJobs(_ jobs: [HighlightJob]) throws {
        self.jobs = jobs
        let onNextSave = onNextSave
        self.onNextSave = nil
        onNextSave?()
    }

    func signalOnNextSave(_ action: @escaping () -> Void) {
        onNextSave = action
    }
}

nonisolated private final class TaskSettlementProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let expectation: XCTestExpectation
    private var didSignal = false

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func signal() {
        let shouldSignal = lock.withLock {
            guard !didSignal else {
                return false
            }
            didSignal = true
            return true
        }
        if shouldSignal {
            expectation.fulfill()
        }
    }
}

nonisolated private final class SettlementAnalyticsTracker: AnalyticsTracking, @unchecked Sendable {
    private let lock = NSLock()
    private let settlementProbe: TaskSettlementProbe
    private var storedEvents: [AnalyticsEvent] = []

    init(settlementProbe: TaskSettlementProbe) {
        self.settlementProbe = settlementProbe
    }

    var events: [AnalyticsEvent] {
        lock.withLock { storedEvents }
    }

    func track(_ event: AnalyticsEvent) {
        lock.withLock {
            storedEvents.append(event)
        }
        settlementProbe.signal()
    }
}

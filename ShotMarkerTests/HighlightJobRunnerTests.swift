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
    func testRunCompletesJobAndReportsProgressWithoutSavingToPhotos() async throws {
        let fileStore = HighlightJobFileStore(baseDirectoryURL: temporaryDirectory)
        let exportedURL = temporaryDirectory.appendingPathComponent("export.mov")
        try Data([1, 2, 3]).write(to: exportedURL)
        let markerLabelStyle = MarkerLabelStyle(
            fontSizeRatio: 0.14,
            normalizedCenterX: 0.7,
            normalizedCenterY: 0.35,
            textOpacity: 0.8,
            backgroundOpacity: 0.25,
        )
        let job = try makeJob(status: .queued, markerLabelStyle: markerLabelStyle)
        var observedStatuses: [HighlightJobStatus] = []
        var receivedStyle: MarkerLabelStyle?
        let runner = HighlightJobRunner(
            fileStore: fileStore,
            makeHighlightClip: { _, markerLabelStyle, progressHandler, _ in
                receivedStyle = markerLabelStyle
                progressHandler(HighlightClipGenerationProgress(completedMarkerCount: 0, totalMarkerCount: 1))
                progressHandler(HighlightClipGenerationProgress(completedMarkerCount: 1, totalMarkerCount: 1))
                return exportedURL
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
        XCTAssertEqual(observedStatuses, [.running, .running, .running, .completed])
        XCTAssertEqual(receivedStyle, job.clipSettings.markerLabelStyle)
    }

    @MainActor
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
        let runner = try makeSuccessfulRunner { received = $0 }

        let completed = try await runner.run(job: job) { _ in }

        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(received, [snapshot.highlightClipSegment])
        XCTAssertEqual(received.first?.start, 1.2)
        XCTAssertEqual(received.first?.duration, 3.4)
    }

    @MainActor
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

    @MainActor
    func testInconsistentClipPlanFieldsFailWithoutExporting() async throws {
        let job = try makeJob(status: .queued)
        let markerID = job.trainingSession.events[0].id
        let validSnapshot = ConfirmedHighlightSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000030202")!,
            videoID: "video",
            markerIDs: [markerID],
            start: 1.2,
            duration: 3.4,
            markerNumberLowerBound: 1,
            markerNumberUpperBound: 1,
            markerTotalCount: 1,
        )
        let invalidSnapshot = ConfirmedHighlightSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000030203")!,
            videoID: "video",
            markerIDs: [markerID],
            start: 1.25,
            duration: 3.4,
            markerNumberLowerBound: 1,
            markerNumberUpperBound: 1,
            markerTotalCount: 1,
        )
        let cases: [(name: String, version: Int?, segments: [ConfirmedHighlightSegment]?, message: String)] = [
            (
                "snapshot without version",
                nil,
                [validSnapshot],
                "任务缺少片段计划版本，请重新创建集锦。"
            ),
            (
                "version one without snapshot",
                1,
                nil,
                "任务缺少已确认片段，请重新创建集锦。"
            ),
            (
                "version one empty snapshot",
                1,
                [],
                "任务的已确认片段无效，请重新创建集锦。"
            ),
            (
                "unsupported version",
                2,
                [validSnapshot],
                "任务使用了不支持的片段计划版本，请重新创建集锦。"
            ),
            (
                "version one invalid snapshot",
                1,
                [invalidSnapshot],
                "任务的已确认片段无效，请重新创建集锦。"
            ),
        ]

        for testCase in cases {
            var input = job
            input.clipPlanVersion = testCase.version
            input.confirmedSegments = testCase.segments
            var didExport = false
            let runner = try makeSuccessfulRunner { _ in didExport = true }

            let failed = try await runner.run(job: input) { _ in }

            XCTAssertEqual(failed.status, .failed, testCase.name)
            XCTAssertEqual(failed.errorMessage, testCase.message, testCase.name)
            XCTAssertFalse(didExport, testCase.name)
        }
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
            makeHighlightClip: { _, _, _, _ in
                XCTFail("Should not export without matching markers")
                return URL(fileURLWithPath: "/tmp/unused.mov")
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

    @MainActor
    private func makeJob(
        status: HighlightJobStatus,
        selectedVideos: [HighlightJobVideo]? = nil,
        markerLabelStyle: MarkerLabelStyle = .default,
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

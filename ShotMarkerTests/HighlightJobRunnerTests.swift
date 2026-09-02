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

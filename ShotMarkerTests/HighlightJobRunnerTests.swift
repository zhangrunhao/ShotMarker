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

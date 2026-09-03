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
        let markerLabelStyle = MarkerLabelStyle(
            fontSizeRatio: 0.13,
            normalizedCenterX: 0.7,
            normalizedCenterY: 0.25,
            textOpacity: 0.85,
            backgroundOpacity: 0.4,
        )
        let job = try makeJob(status: .completed, markerLabelStyle: markerLabelStyle)

        try store.saveJobs([job])

        XCTAssertEqual(try store.loadJobs(), [job])
        XCTAssertEqual(try store.loadJobs().first?.clipSettings.markerLabelStyle, markerLabelStyle)
    }

    func testLoadVersion12JobAddsDefaultNestedMarkerStyle() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/HighlightJob-1.2.json")
        let jobs = try HighlightJobStore(fileURL: fixtureURL).loadJobs()
        let job = try XCTUnwrap(jobs.first)

        XCTAssertEqual(job.clipSettings.secondsBeforeMarker, 7)
        XCTAssertEqual(job.clipSettings.secondsAfterMarker, 3)
        XCTAssertEqual(job.clipSettings.markerLabelStyle, .default)
    }

    func testVersionOneJobRoundTripKeepsExactConfirmedSegments() throws {
        let segment = ConfirmedHighlightSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000060001")!,
            videoID: "photo-asset-id",
            markerIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000010101")!],
            start: 12.3,
            duration: 4.5,
            markerNumberLowerBound: 1,
            markerNumberUpperBound: 1,
            markerTotalCount: 1,
        )
        var job = try makeJob(status: .interrupted)
        job.clipPlanVersion = 1
        job.confirmedSegments = [segment]
        let fileURL = temporaryDirectory.appendingPathComponent("highlight-jobs.json")
        let store = HighlightJobStore(fileURL: fileURL)

        try store.saveJobs([job])
        let loaded = try XCTUnwrap(store.loadJobs().first)

        XCTAssertEqual(loaded.clipPlanVersion, 1)
        XCTAssertEqual(loaded.confirmedSegments, [segment])
    }

    func testVersion12AndVersion13FixturesDecodeWithoutClipSnapshot() throws {
        for fixture in ["HighlightJob-1.2.json", "HighlightJob-1.3.json"] {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/\(fixture)")
            let job = try XCTUnwrap(HighlightJobStore(fileURL: url).loadJobs().first)

            XCTAssertNil(job.clipPlanVersion, fixture)
            XCTAssertNil(job.confirmedSegments, fixture)
        }
    }

    func testLegacyEncodingDoesNotInventVersionOrConfirmedSegments() throws {
        let job = try makeJob(status: .interrupted)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any],
        )

        XCTAssertNil(object["clipPlanVersion"])
        XCTAssertNil(object["confirmedSegments"])
    }

    func testMalformedConfirmedSegmentsDecodesAsInvalidRunnerSentinel() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(try makeJob(status: .interrupted)),
            ) as? [String: Any],
        )
        object["clipPlanVersion"] = 1
        object["confirmedSegments"] = "damaged"
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HighlightJob.self, from: data)

        XCTAssertEqual(decoded.clipPlanVersion, 1)
        XCTAssertEqual(decoded.confirmedSegments, [])
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
                "photoLibrarySavedAt",
                "photoLibrarySaveErrorMessage",
                "errorMessage",
                "createdAt",
                "updatedAt",
            ]),
        )

        var versionOneJob = job
        versionOneJob.clipPlanVersion = 1
        versionOneJob.confirmedSegments = [
            ConfirmedHighlightSegment(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000060002")!,
                videoID: "photo-asset-id",
                markerIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000010101")!],
                start: 12.3,
                duration: 4.5,
                markerNumberLowerBound: 1,
                markerNumberUpperBound: 1,
                markerTotalCount: 1,
            ),
        ]
        let versionOneObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(versionOneJob),
            ) as? [String: Any],
        )
        XCTAssertEqual(
            Set(versionOneObject.keys),
            Set(jsonObject.keys).union(["clipPlanVersion", "confirmedSegments"]),
        )
    }

    private func makeJob(
        id: String = "00000000-0000-0000-0000-000000010000",
        status: HighlightJobStatus,
        markerLabelStyle: MarkerLabelStyle = .default,
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
            clipSettings: ClipSettings(
                secondsBeforeMarker: 9,
                secondsAfterMarker: 4,
                markerLabelStyle: markerLabelStyle,
            ),
            status: status,
            progress: HighlightJobProgress(completedMarkerCount: 1, totalMarkerCount: 3),
            outputVideoPath: status == .completed ? "HighlightJobs/Outputs/job/highlight.mov" : nil,
            errorMessage: status == .failed ? "导出失败" : nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 3_100),
        )
    }
}

@testable import ShotMarker
import XCTest

final class HighlightClipReviewIdentityBuilderTests: XCTestCase {
    func testIdenticalTrainingAndOrderedVideosProduceIdenticalKey() throws {
        let session = makeSession()
        let videos = [
            makeVideo(id: "runtime-a", source: source("asset-a"), start: 100, duration: 60),
            makeVideo(id: "runtime-b", source: source("asset-b"), start: 160, duration: 45),
        ]

        XCTAssertEqual(
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: videos),
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: videos),
        )
    }

    func testVideoOrderChangesCombination() throws {
        let session = makeSession()
        let first = makeVideo(id: "a", source: source("asset-a"), start: 100, duration: 60)
        let second = makeVideo(id: "b", source: source("asset-b"), start: 160, duration: 45)

        XCTAssertNotEqual(
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [first, second]),
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [second, first]),
        )
    }

    func testTrainingContentChangesCombinationEvenWhenIDMatches() throws {
        let original = makeSession()
        let changedStart = TrainingSession(
            id: original.id,
            startedAt: original.startedAt.addingTimeInterval(0.001),
            endedAt: original.endedAt,
            events: original.events,
        )
        let changedMarker = TrainingSession(
            id: original.id,
            startedAt: original.startedAt,
            endedAt: original.endedAt,
            events: [
                ShotMarkerEvent(id: original.events[0].id,
                                markedAt: original.events[0].markedAt.addingTimeInterval(0.001)),
            ],
        )
        let changedMarkerID = TrainingSession(
            id: original.id,
            startedAt: original.startedAt,
            endedAt: original.endedAt,
            events: [
                ShotMarkerEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                    markedAt: original.events[0].markedAt,
                ),
            ],
        )
        let videos = [makeVideo()]

        let key = try HighlightClipReviewIdentityBuilder.combinationKey(for: original, videos: videos)
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: changedStart, videos: videos))
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: changedMarker, videos: videos))
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: changedMarkerID, videos: videos))
    }

    func testMetadataAndSourceChangesCombination() throws {
        let session = makeSession()
        let base = makeVideo()
        let changedSource = makeVideo(source: source("different"))
        let changedDate = makeVideo(start: 100.001)
        let changedDuration = makeVideo(duration: 60.01)
        let key = try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [base])

        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [changedSource]))
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [changedDate]))
        XCTAssertNotEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [changedDuration]))
    }

    func testMillisecondAndSixHundredTickNormalizationRemoveTailNoise() throws {
        let session = makeSession(startedAt: 10.000_000_1)
        let noisySession = makeSession(startedAt: 10.000_000_2)
        let video = makeVideo(start: 100.000_000_1, duration: 60.000_000_1)
        let noisyVideo = makeVideo(start: 100.000_000_2, duration: 60.000_000_2)

        XCTAssertEqual(
            try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: [video]),
            try HighlightClipReviewIdentityBuilder.combinationKey(for: noisySession, videos: [noisyVideo]),
        )
    }

    func testMarkerTieUsesUUIDAndVideoOrderRemainsUnsorted() throws {
        let date = Date(timeIntervalSince1970: 20)
        let high = ShotMarkerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            markedAt: date,
        )
        let low = ShotMarkerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            markedAt: date,
        )
        let session = TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            startedAt: date,
            endedAt: date.addingTimeInterval(5),
            events: [high, low],
        )

        let identity = HighlightClipReviewIdentityBuilder.trainingIdentity(for: session)
        XCTAssertEqual(identity.markers.map(\.id), [low.id, high.id])
    }

    func testSettingsAndLabelStyleAreNotCombinationInputs() throws {
        let session = makeSession()
        let videos = [makeVideo()]
        let key = try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: videos)
        var settings = ClipSettings.default
        settings.secondsBeforeMarker = 20
        settings.secondsAfterMarker = 20

        XCTAssertNotEqual(settings, .default)
        XCTAssertEqual(key, try HighlightClipReviewIdentityBuilder.combinationKey(for: session, videos: videos))
    }

    func testMissingStableSourceIdentityRejectsCombination() {
        let video = SelectedTrainingVideo(
            id: "file:///temporary.mov",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        XCTAssertThrowsError(
            try HighlightClipReviewIdentityBuilder.combinationKey(for: makeSession(), videos: [video]),
        ) {
            XCTAssertEqual($0 as? HighlightClipReviewIdentityError, .missingSourceIdentity)
        }
    }

    func testDuplicateCompleteVideoIdentityIsRejectedEvenWhenRuntimeIDsDiffer() {
        let source = HighlightClipReviewSourceIdentity.photoLibraryAsset("same-asset")
        let videos = [
            makeVideo(id: "runtime-a", source: source, start: 100),
            makeVideo(id: "runtime-b", source: source, start: 100),
        ]

        XCTAssertThrowsError(
            try HighlightClipReviewIdentityBuilder.combinationKey(
                for: makeSession(),
                videos: videos,
            ),
        ) {
            XCTAssertEqual($0 as? HighlightClipReviewIdentityError, .duplicateVideoIdentity)
        }
    }
}

private extension HighlightClipReviewIdentityBuilderTests {
    func source(_ value: String) -> HighlightClipReviewSourceIdentity {
        .photoLibraryAsset(value)
    }

    func makeVideo(
        id: String = "runtime-video",
        source: HighlightClipReviewSourceIdentity = .photoLibraryAsset("asset-a"),
        start: TimeInterval = 100,
        duration: TimeInterval = 60,
    ) -> SelectedTrainingVideo {
        SelectedTrainingVideo(
            id: id,
            recordedStartAt: Date(timeIntervalSince1970: start),
            duration: duration,
            reviewSourceIdentity: source,
        )
    }

    func makeSession(startedAt: TimeInterval = 10) -> TrainingSession {
        let start = Date(timeIntervalSince1970: startedAt)
        return TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            events: [
                ShotMarkerEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                    markedAt: start.addingTimeInterval(20),
                ),
            ],
        )
    }
}

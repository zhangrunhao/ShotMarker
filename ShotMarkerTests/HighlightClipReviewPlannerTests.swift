@testable import ShotMarker
import XCTest

final class HighlightClipReviewPlannerTests: XCTestCase {
    func testNormalizedTenthsUsesSixHundredTimescaleAndNearestTenth() {
        XCTAssertEqual(HighlightClipReviewPlanner.normalizedTenths(10.04), 10.0)
        XCTAssertEqual(HighlightClipReviewPlanner.normalizedTenths(10.06), 10.1)
        XCTAssertEqual(HighlightClipReviewPlanner.exportTimescale, 600)
    }

    func testMovingRangeClampsAtBothVideoEdgesAndKeepsLength() throws {
        let item = makeItem(start: 2, duration: 4)

        let movedEarlier = try HighlightClipReviewPlanner.apply(
            .moveBy(-20),
            to: item,
            videoDuration: 12,
        )
        let movedLater = try HighlightClipReviewPlanner.apply(
            .moveBy(20),
            to: item,
            videoDuration: 12,
        )

        XCTAssertEqual(
            HighlightClipRange(start: movedEarlier.start, duration: movedEarlier.duration),
            HighlightClipRange(start: 0, duration: 4),
        )
        XCTAssertEqual(
            HighlightClipRange(start: movedLater.start, duration: movedLater.duration),
            HighlightClipRange(start: 8, duration: 4),
        )
    }

    func testHandlesStopAtMinimumDurationWithoutCrossing() throws {
        let item = makeItem(start: 2, duration: 4)

        let movedStart = try HighlightClipReviewPlanner.apply(
            .setStart(10),
            to: item,
            videoDuration: 12,
        )
        let movedEnd = try HighlightClipReviewPlanner.apply(
            .setEnd(2),
            to: item,
            videoDuration: 12,
        )

        XCTAssertEqual(movedStart.start, 5)
        XCTAssertEqual(movedStart.duration, 1)
        XCTAssertEqual(movedEnd.start, 2)
        XCTAssertEqual(movedEnd.duration, 1)
    }

    func testShortVideoCanOnlyUseItsCompleteRange() throws {
        let item = makeItem(start: 0, duration: 0.6)

        let edited = try HighlightClipReviewPlanner.apply(
            .replace(start: 0.2, duration: 0.2),
            to: item,
            videoDuration: 0.6,
        )

        XCTAssertEqual(edited.start, 0)
        XCTAssertEqual(edited.duration, 0.6)
    }

    func testRangeMayMoveAwayFromMarkerWithoutMutatingReference() throws {
        let item = makeItem(start: 8, duration: 4)

        let edited = try HighlightClipReviewPlanner.apply(
            .moveBy(15),
            to: item,
            videoDuration: 30,
        )

        XCTAssertEqual(edited.range, HighlightClipRange(start: 23, duration: 4))
        XCTAssertEqual(edited.markerReferences, item.markerReferences)
        XCTAssertFalse(
            (edited.range.start ... edited.range.end).contains(edited.markerReferences[0].timeInVideo),
        )
    }

    func testValidatedRangeRejectsNonFiniteZeroAndOutOfBoundsValues() {
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validatedRange(
                HighlightClipRange(start: .nan, duration: 1),
                videoDuration: 10,
            ),
        )
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validatedRange(
                HighlightClipRange(start: 0, duration: 0),
                videoDuration: 10,
            ),
        )
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validatedRange(
                HighlightClipRange(start: 9.5, duration: 1),
                videoDuration: 10,
            ),
        )
    }

    private func makeItem(
        start: TimeInterval,
        duration: TimeInterval,
    ) -> HighlightClipReviewItem {
        HighlightClipReviewItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000050001")!,
            videoID: "video",
            markerReferences: [
                HighlightClipMarkerReference(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000050101")!,
                    markedAt: Date(timeIntervalSince1970: 120),
                    timeInVideo: 20,
                    originalMatchedNumber: 1,
                ),
            ],
            defaultStart: start,
            defaultDuration: duration,
            start: start,
            duration: duration,
            isIncluded: true,
        )
    }
}

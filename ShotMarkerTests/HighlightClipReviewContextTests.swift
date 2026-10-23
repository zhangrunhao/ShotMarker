@testable import ShotMarker
import XCTest

final class HighlightClipReviewContextTests: XCTestCase {
    func testCandidateNumberUsesOriginalItemOrderRegardlessOfInclusionOrMarkerCount() {
        let first = makeItem(number: 1, start: 0, duration: 2, markerCount: 3)
        var second = makeItem(number: 4, start: 5, duration: 2)
        let third = makeItem(number: 5, start: 10, duration: 2)
        second.isIncluded = false

        let context = makeContext(items: [first, second, third], workingItem: third)

        XCTAssertEqual(context.candidateNumber, 3)
        XCTAssertEqual(context.candidateCount, 3)
        XCTAssertEqual(context.previousItem?.id, second.id)
        XCTAssertNil(context.nextItem)
        XCTAssertEqual(context.relationships.first?.candidateNumber, 2)
    }

    func testNeighborsRetainOriginalOrderWhenWorkingRangeMovesAcrossThem() {
        let first = makeItem(number: 1, start: 0, duration: 2)
        let second = makeItem(number: 2, start: 5, duration: 2)
        let third = makeItem(number: 3, start: 10, duration: 2)
        var working = second
        working.start = 20

        let context = makeContext(items: [first, second, third], workingItem: working)

        XCTAssertEqual(context.previousItem?.id, first.id)
        XCTAssertEqual(context.nextItem?.id, third.id)
        XCTAssertEqual(context.relationships.map(\.position), [.previous, .next])
        XCTAssertEqual(context.relationships.map(\.candidateNumber), [1, 3])
        XCTAssertEqual(context.relationships.map(\.separation), [.gap(seconds: 18), .gap(seconds: 8)])
    }

    func testFirstCandidateDoesNotWrapPreviousNeighborToLastCandidate() {
        let first = makeItem(number: 1, start: 0, duration: 2)
        let second = makeItem(number: 2, start: 5, duration: 2)

        let context = makeContext(items: [first, second], workingItem: first)

        XCTAssertNil(context.previousItem)
        XCTAssertEqual(context.nextItem?.id, second.id)
        XCTAssertEqual(context.relationships.map(\.position), [.next])
    }

    func testUnknownWorkingIdentityHasNoCandidateNumberOrNeighbors() {
        let first = makeItem(number: 1, start: 0, duration: 2)
        let unknown = makeItem(number: 2, start: 5, duration: 2)

        let context = makeContext(items: [first], workingItem: unknown)

        XCTAssertNil(context.candidateNumber)
        XCTAssertNil(context.previousItem)
        XCTAssertNil(context.nextItem)
        XCTAssertTrue(context.relationships.isEmpty)
    }

    func testDifferentVideosHaveNoComparableDistanceOrTimelineOverlay() throws {
        let first = makeItem(number: 1, start: 1, duration: 4, videoID: "video-a")
        let second = makeItem(number: 2, start: 2, duration: 2, videoID: "video-b")

        let relation = try XCTUnwrap(makeContext(items: [first, second], workingItem: second).relationships.first)

        XCTAssertEqual(relation.separation, .differentVideo)
        XCTAssertFalse(relation.willMerge)
        XCTAssertNil(relation.timelineRange)
    }

    func testContainedNeighborReportsOnlySharedDuration() throws {
        let first = makeItem(number: 1, start: 4, duration: 2)
        let second = makeItem(number: 2, start: 0, duration: 10)

        let relation = try XCTUnwrap(makeContext(items: [first, second], workingItem: second).relationships.first)

        XCTAssertEqual(relation.itemID, first.id)
        XCTAssertEqual(relation.separation, .overlap(seconds: 2))
        XCTAssertEqual(relation.timelineRange, HighlightClipRange(start: 4, duration: 2))
        XCTAssertTrue(relation.willMerge)
    }

    func testTouchingRangesReportZeroGapAndMerge() throws {
        let first = makeItem(number: 1, start: 0, duration: 2)
        let second = makeItem(number: 2, start: 2, duration: 2)

        let relation = try XCTUnwrap(makeContext(items: [first, second], workingItem: second).relationships.first)

        XCTAssertEqual(relation.separation, .gap(seconds: 0))
        XCTAssertTrue(relation.willMerge)
    }

    func testOneSecondGapMergesButLargerGapDoesNot() throws {
        let first = makeItem(number: 1, start: 0, duration: 2)
        for (start, expectedMerge) in [(3.0, true), (3.1, false)] {
            let second = makeItem(number: 2, start: start, duration: 2)

            let relation = try XCTUnwrap(makeContext(items: [first, second], workingItem: second).relationships.first)

            XCTAssertEqual(relation.willMerge, expectedMerge, "start: \(start)")
        }
    }

    func testReversedRangesUseSymmetricGapAndRetainCandidatePosition() throws {
        let first = makeItem(number: 1, start: 10, duration: 2)
        let second = makeItem(number: 2, start: 5, duration: 4)

        let relation = try XCTUnwrap(makeContext(items: [first, second], workingItem: second).relationships.first)

        XCTAssertEqual(relation.position, .previous)
        XCTAssertEqual(relation.separation, .gap(seconds: 1))
        XCTAssertTrue(relation.willMerge)
    }

    func testExcludedNeighborRemainsVisibleAndBreaksMergeChain() throws {
        let first = makeItem(number: 1, start: 0, duration: 10)
        var second = makeItem(number: 2, start: 1, duration: 2)
        let third = makeItem(number: 3, start: 2, duration: 3)
        second.isIncluded = false

        let context = makeContext(items: [first, second, third], workingItem: third)
        let relation = try XCTUnwrap(context.relationships.first)

        XCTAssertEqual(context.previousItem?.id, second.id)
        XCTAssertEqual(relation.itemID, second.id)
        XCTAssertFalse(relation.isIncluded)
        XCTAssertEqual(relation.separation, .overlap(seconds: 1))
        XCTAssertFalse(relation.willMerge)
    }

    func testWorkingRangeControlsRelationAndMergeBeforeItIsSaved() throws {
        let first = makeItem(number: 1, start: 0, duration: 4)
        let second = makeItem(number: 2, start: 10, duration: 2)
        var working = second
        working.start = 3

        let relation = try XCTUnwrap(makeContext(items: [first, second], workingItem: working).relationships.first)

        XCTAssertEqual(relation.separation, .overlap(seconds: 1))
        XCTAssertTrue(relation.willMerge)
        XCTAssertEqual(second.start, 10)
    }

    func testWorkingExclusionPreventsMergeBeforeItIsSaved() throws {
        let first = makeItem(number: 1, start: 0, duration: 4)
        let second = makeItem(number: 2, start: 3, duration: 2)
        var working = second
        working.isIncluded = false

        let relation = try XCTUnwrap(makeContext(items: [first, second], workingItem: working).relationships.first)

        XCTAssertEqual(relation.separation, .overlap(seconds: 1))
        XCTAssertTrue(relation.isIncluded)
        XCTAssertFalse(relation.willMerge)
    }

    func testMergePredictionIncludesEarlierRangeThatBridgesAdjacentCandidates() throws {
        let first = makeItem(number: 1, start: 0, duration: 30)
        let second = makeItem(number: 2, start: 1, duration: 2)
        let third = makeItem(number: 3, start: 20, duration: 2)

        let relation = try XCTUnwrap(makeContext(items: [first, second, third], workingItem: third).relationships.first)

        XCTAssertEqual(relation.itemID, second.id)
        XCTAssertEqual(relation.separation, .gap(seconds: 17))
        XCTAssertTrue(relation.willMerge)
    }

    func testPlanningFailureKeepsDistanceButDoesNotPromiseMerge() throws {
        let first = makeItem(number: 1, start: 0, duration: 4)
        let second = makeItem(number: 2, start: 3, duration: 2)
        let context = HighlightClipReviewContext(items: [first, second], workingItem: second, videos: [])

        let relation = try XCTUnwrap(context.relationships.first)

        XCTAssertEqual(relation.separation, .overlap(seconds: 1))
        XCTAssertFalse(relation.willMerge)
    }

    private func makeContext(
        items: [HighlightClipReviewItem],
        workingItem: HighlightClipReviewItem,
    ) -> HighlightClipReviewContext {
        HighlightClipReviewContext(
            items: items,
            workingItem: workingItem,
            videos: ["video", "video-a", "video-b"].map {
                SelectedTrainingVideo(id: $0, recordedStartAt: Date(timeIntervalSince1970: 0), duration: 60)
            },
        )
    }

    private func makeItem(
        number: Int,
        start: TimeInterval,
        duration: TimeInterval,
        videoID: String = "video",
        markerCount: Int = 1,
    ) -> HighlightClipReviewItem {
        HighlightClipReviewItem(
            id: UUID(),
            videoID: videoID,
            markerReferences: (0 ..< markerCount).map { offset in
                HighlightClipMarkerReference(
                    id: UUID(),
                    markedAt: Date(timeIntervalSince1970: start),
                    timeInVideo: start,
                    originalMatchedNumber: number + offset,
                )
            },
            defaultStart: start,
            defaultDuration: duration,
            start: start,
            duration: duration,
            isIncluded: true,
        )
    }
}

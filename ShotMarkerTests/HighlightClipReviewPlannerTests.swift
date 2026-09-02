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

    func testDefaultDraftReusesLegacyRangesSelectionOrderAndMergedMarkerReferences() throws {
        let first = marker(id: 0x201, at: 110)
        let second = marker(id: 0x202, at: 114)
        let unmatched = marker(id: 0x203, at: 500)
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 520),
            events: [unmatched, second, first],
        )
        let preferredVideo = SelectedTrainingVideo(
            id: "preferred",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let overlappingVideo = SelectedTrainingVideo(
            id: "overlap",
            recordedStartAt: Date(timeIntervalSince1970: 90),
            duration: 90,
        )
        let settings = ClipSettings(secondsBeforeMarker: 6, secondsAfterMarker: 2)

        let legacy = VideoClipSegmentPlanner.highlightPlan(
            for: session,
            videos: [preferredVideo, overlappingVideo],
            clipSettings: settings,
        )
        let draft = HighlightClipReviewPlanner.makeDraft(
            for: session,
            videos: [preferredVideo, overlappingVideo],
            clipSettings: settings,
        )

        XCTAssertEqual(draft.totalMarkerCount, 3)
        XCTAssertEqual(draft.matchedMarkerCount, 2)
        XCTAssertEqual(draft.unmatchedMarkerCount, 1)
        XCTAssertEqual(draft.items.count, legacy.segments.count)
        XCTAssertEqual(draft.items.map(\.videoID), legacy.segments.map(\.videoID))
        XCTAssertEqual(draft.items.map(\.range), legacy.segments.map {
            HighlightClipRange(start: $0.start, duration: $0.duration)
        })
        XCTAssertEqual(draft.items.first?.markerReferences.map(\.id), [first.id, second.id])
        XCTAssertEqual(draft.items.first?.markerReferences.map(\.originalMatchedNumber), [1, 2])
        XCTAssertTrue(draft.items.allSatisfy(\.isIncluded))
    }

    func testExcludedCardKeepsOriginalIdentityWhileIncludedCardsRenumber() throws {
        var items = [
            makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 2),
            makeItem(idSuffix: 2, markerNumbers: [2, 3], start: 5, duration: 2),
            makeItem(idSuffix: 3, markerNumbers: [4], start: 10, duration: 2),
        ]
        items[1].isIncluded = false

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: items,
            videos: [makeVideo()],
        )

        XCTAssertEqual(summary.includedMarkerCount, 2)
        XCTAssertEqual(summary.excludedMarkerCount, 2)
        XCTAssertEqual(summary.displayNumberRangesByItemID[items[0].id], 1 ... 1)
        XCTAssertEqual(summary.displayNumberRangesByItemID[items[1].id], 2 ... 3)
        XCTAssertEqual(summary.displayNumberRangesByItemID[items[2].id], 2 ... 2)
        XCTAssertEqual(summary.finalSegments.map(\.markerIDs), [
            items[0].markerReferences.map(\.id),
            items[2].markerReferences.map(\.id),
        ])
    }

    func testFinalMergeUsesSymmetricGapForReversedEditedRanges() throws {
        let first = makeItem(idSuffix: 1, markerNumbers: [1], start: 10, duration: 2)
        let second = makeItem(idSuffix: 2, markerNumbers: [2], start: 5, duration: 4)

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: [first, second],
            videos: [makeVideo()],
        )

        XCTAssertEqual(summary.finalSegments.count, 1)
        XCTAssertEqual(summary.finalSegments[0].start, 5)
        XCTAssertEqual(summary.finalSegments[0].duration, 7)
        XCTAssertEqual(summary.mergingItemIDs, [first.id, second.id])
    }

    func testExcludedMiddleCardBreaksTheFinalMergeChain() throws {
        let first = makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 4)
        var middle = makeItem(idSuffix: 2, markerNumbers: [2], start: 20, duration: 2)
        let third = makeItem(idSuffix: 3, markerNumbers: [3], start: 3, duration: 4)
        middle.isIncluded = false

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: [first, middle, third],
            videos: [makeVideo()],
        )

        XCTAssertEqual(summary.finalSegments.count, 2)
        XCTAssertTrue(summary.mergingItemIDs.isEmpty)
    }

    func testDefaultDraftUsesOnlyMatchedMarkersAndNumbersThemContinuously() {
        let first = marker(id: 0x301, at: 110)
        let unmatched = marker(id: 0x302, at: 500)
        let second = marker(id: 0x303, at: 130)
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 520),
            events: [second, unmatched, first],
        )

        let draft = HighlightClipReviewPlanner.makeDraft(
            for: session,
            videos: [makeVideo(duration: 60, recordedStartAt: 100)],
            clipSettings: ClipSettings(secondsBeforeMarker: 2, secondsAfterMarker: 1),
        )

        XCTAssertEqual(draft.items.flatMap(\.markerReferences).map(\.id), [first.id, second.id])
        XCTAssertEqual(
            draft.items.flatMap(\.markerReferences).map(\.originalMatchedNumber),
            [1, 2],
        )
        XCTAssertEqual(draft.unmatchedMarkerCount, 1)
    }

    func testFinalMergeJoinsExactlyOneSecondGap() throws {
        let first = makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 2)
        let second = makeItem(idSuffix: 2, markerNumbers: [2], start: 3, duration: 2)

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: [first, second],
            videos: [makeVideo()],
        )

        XCTAssertEqual(summary.finalSegments.count, 1)
        XCTAssertEqual(summary.finalSegments[0].start, 0)
        XCTAssertEqual(summary.finalSegments[0].duration, 5)
    }

    func testFinalMergeDoesNotJoinGapGreaterThanOneSecond() throws {
        let first = makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 2)
        let second = makeItem(idSuffix: 2, markerNumbers: [2], start: 3.1, duration: 2)

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: [first, second],
            videos: [makeVideo()],
        )

        XCTAssertEqual(summary.finalSegments.count, 2)
        XCTAssertTrue(summary.mergingItemIDs.isEmpty)
    }

    func testFinalMergeDoesNotJoinDifferentVideos() throws {
        let first = makeItem(
            idSuffix: 1,
            markerNumbers: [1],
            start: 0,
            duration: 2,
            videoID: "video-a",
        )
        let second = makeItem(
            idSuffix: 2,
            markerNumbers: [2],
            start: 2,
            duration: 2,
            videoID: "video-b",
        )

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: [first, second],
            videos: [makeVideo(id: "video-a"), makeVideo(id: "video-b")],
        )

        XCTAssertEqual(summary.finalSegments.count, 2)
        XCTAssertTrue(summary.mergingItemIDs.isEmpty)
    }

    func testFinalMergeUnionsThreeCardsAndAllMarkerIDs() throws {
        let first = makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 2)
        let second = makeItem(idSuffix: 2, markerNumbers: [2, 3], start: 2.5, duration: 2)
        let third = makeItem(idSuffix: 3, markerNumbers: [4], start: 5, duration: 2)

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: [first, second, third],
            videos: [makeVideo()],
        )

        let segment = try XCTUnwrap(summary.finalSegments.first)
        XCTAssertEqual(summary.finalSegments.count, 1)
        XCTAssertEqual(segment.start, 0)
        XCTAssertEqual(segment.duration, 7)
        XCTAssertEqual(segment.markerIDs, [first, second, third].flatMap(\.markerReferences).map(\.id))
        XCTAssertEqual(segment.markerNumberLowerBound, 1)
        XCTAssertEqual(segment.markerNumberUpperBound, 4)
        XCTAssertEqual(segment.markerTotalCount, 4)
        XCTAssertEqual(summary.mergingItemIDs, [first.id, second.id, third.id])
    }

    func testSummaryDurationUsesMergedUnionWithoutDoubleCounting() throws {
        let first = makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 4)
        let second = makeItem(idSuffix: 2, markerNumbers: [2], start: 2, duration: 4)

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: [first, second],
            videos: [makeVideo()],
        )

        XCTAssertEqual(summary.totalDuration, 6)
    }

    func testSummaryRepresentsNoIncludedItemsWithoutFinalSegments() throws {
        var first = makeItem(idSuffix: 1, markerNumbers: [1], start: 0, duration: 2)
        var second = makeItem(idSuffix: 2, markerNumbers: [2, 3], start: 5, duration: 2)
        first.isIncluded = false
        second.isIncluded = false

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: [first, second],
            videos: [makeVideo()],
        )

        XCTAssertEqual(summary.includedMarkerCount, 0)
        XCTAssertEqual(summary.excludedMarkerCount, 3)
        XCTAssertTrue(summary.finalSegments.isEmpty)
        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertEqual(summary.displayNumberRangesByItemID[first.id], 1 ... 1)
        XCTAssertEqual(summary.displayNumberRangesByItemID[second.id], 2 ... 3)
    }

    func testValidateConfirmedSegmentsRejectsMissingVideo() {
        let segment = makeConfirmedSegment(videoID: "missing")

        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validateConfirmedSegments(
                [segment],
                videos: [makeVideo()],
                validMarkerIDs: Set(segment.markerIDs),
            ),
        ) { error in
            XCTAssertEqual(error as? HighlightClipReviewPlanningError, .sourceVideoMissing)
        }
    }

    func testValidateConfirmedSegmentsRejectsNonFiniteAndNonTenthRanges() {
        let nonFinite = makeConfirmedSegment(start: .nan)
        let nonTenth = makeConfirmedSegment(start: 1.05)

        for segment in [nonFinite, nonTenth] {
            XCTAssertThrowsError(
                try HighlightClipReviewPlanner.validateConfirmedSegments(
                    [segment],
                    videos: [makeVideo()],
                    validMarkerIDs: Set(segment.markerIDs),
                ),
            ) { error in
                XCTAssertEqual(error as? HighlightClipReviewPlanningError, .invalidRange)
            }
        }
    }

    func testValidateConfirmedSegmentsRejectsEmptyMarkersDuplicateIDsAndBadNumbering() {
        let missingMarkers = makeConfirmedSegment(markerIDs: [])
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validateConfirmedSegments(
                [missingMarkers],
                videos: [makeVideo()],
                validMarkerIDs: [],
            ),
        ) { error in
            XCTAssertEqual(error as? HighlightClipReviewPlanningError, .missingMarkers)
        }

        let first = makeConfirmedSegment(
            idSuffix: 1,
            markerIDs: [fixedUUID(90_101)],
            lowerBound: 1,
            upperBound: 1,
            totalCount: 2,
        )
        let duplicateID = makeConfirmedSegment(
            idSuffix: 1,
            markerIDs: [fixedUUID(90_102)],
            lowerBound: 2,
            upperBound: 2,
            totalCount: 2,
        )
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validateConfirmedSegments(
                [first, duplicateID],
                videos: [makeVideo()],
                validMarkerIDs: [fixedUUID(90_101), fixedUUID(90_102)],
            ),
        ) { error in
            XCTAssertEqual(error as? HighlightClipReviewPlanningError, .duplicateIdentity)
        }

        let repeatedMarkerID = fixedUUID(90_201)
        let firstRepeatedMarker = makeConfirmedSegment(
            idSuffix: 2,
            markerIDs: [repeatedMarkerID],
            lowerBound: 1,
            upperBound: 1,
            totalCount: 2,
        )
        let secondRepeatedMarker = makeConfirmedSegment(
            idSuffix: 3,
            markerIDs: [repeatedMarkerID],
            lowerBound: 2,
            upperBound: 2,
            totalCount: 2,
        )
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validateConfirmedSegments(
                [firstRepeatedMarker, secondRepeatedMarker],
                videos: [makeVideo()],
                validMarkerIDs: [repeatedMarkerID],
            ),
        ) { error in
            XCTAssertEqual(error as? HighlightClipReviewPlanningError, .duplicateIdentity)
        }

        let badNumbering = makeConfirmedSegment(
            markerIDs: [fixedUUID(90_103)],
            lowerBound: 2,
            upperBound: 2,
            totalCount: 1,
        )
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validateConfirmedSegments(
                [badNumbering],
                videos: [makeVideo()],
                validMarkerIDs: [fixedUUID(90_103)],
            ),
        ) { error in
            XCTAssertEqual(error as? HighlightClipReviewPlanningError, .inconsistentNumbering)
        }
    }

    func testValidateConfirmedSegmentsRejectsMarkerOutsideTrainingSet() {
        let segment = makeConfirmedSegment(markerIDs: [fixedUUID(91_001)])

        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validateConfirmedSegments(
                [segment],
                videos: [makeVideo()],
                validMarkerIDs: [fixedUUID(91_002)],
            ),
        ) { error in
            XCTAssertEqual(error as? HighlightClipReviewPlanningError, .missingMarkers)
        }
    }

    func testValidateConfirmedSegmentsAcceptsShortVideoOnlyForFullRange() throws {
        let fullRange = makeConfirmedSegment(start: 0, duration: 0.6)
        let partialRange = makeConfirmedSegment(start: 0.1, duration: 0.5)
        let shortVideo = makeVideo(duration: 0.6)

        XCTAssertEqual(
            try HighlightClipReviewPlanner.validateConfirmedSegments(
                [fullRange],
                videos: [shortVideo],
                validMarkerIDs: Set(fullRange.markerIDs),
            ),
            [fullRange],
        )
        XCTAssertThrowsError(
            try HighlightClipReviewPlanner.validateConfirmedSegments(
                [partialRange],
                videos: [shortVideo],
                validMarkerIDs: Set(partialRange.markerIDs),
            ),
        ) { error in
            XCTAssertEqual(error as? HighlightClipReviewPlanningError, .invalidRange)
        }
    }

    private func makeItem(
        start: TimeInterval,
        duration: TimeInterval,
    ) -> HighlightClipReviewItem {
        makeItem(
            idSuffix: 1,
            markerNumbers: [1],
            start: start,
            duration: duration,
        )
    }

    private func marker(id: Int, at timestamp: TimeInterval) -> ShotMarkerEvent {
        ShotMarkerEvent(
            id: fixedUUID(id),
            markedAt: Date(timeIntervalSince1970: timestamp),
        )
    }

    private func makeItem(
        idSuffix: Int,
        markerNumbers: [Int],
        start: TimeInterval,
        duration: TimeInterval,
        videoID: String = "video",
    ) -> HighlightClipReviewItem {
        let references = markerNumbers.map { number in
            HighlightClipMarkerReference(
                id: fixedUUID(50_000 + idSuffix * 100 + number),
                markedAt: Date(timeIntervalSince1970: 100 + Double(number)),
                timeInVideo: Double(number),
                originalMatchedNumber: number,
            )
        }
        return HighlightClipReviewItem(
            id: fixedUUID(60_000 + idSuffix),
            videoID: videoID,
            markerReferences: references,
            defaultStart: start,
            defaultDuration: duration,
            start: start,
            duration: duration,
            isIncluded: true,
        )
    }

    private func makeVideo(
        id: String = "video",
        duration: TimeInterval = 30,
        recordedStartAt: TimeInterval = 0,
    ) -> SelectedTrainingVideo {
        SelectedTrainingVideo(
            id: id,
            recordedStartAt: Date(timeIntervalSince1970: recordedStartAt),
            duration: duration,
        )
    }

    private func makeConfirmedSegment(
        idSuffix: Int = 1,
        videoID: String = "video",
        markerIDs: [UUID] = [
            UUID(uuidString: "00000000-0000-0000-0000-000000090001")!,
        ],
        start: TimeInterval = 1,
        duration: TimeInterval = 2,
        lowerBound: Int = 1,
        upperBound: Int = 1,
        totalCount: Int = 1,
    ) -> ConfirmedHighlightSegment {
        ConfirmedHighlightSegment(
            id: fixedUUID(92_000 + idSuffix),
            videoID: videoID,
            markerIDs: markerIDs,
            start: start,
            duration: duration,
            markerNumberLowerBound: lowerBound,
            markerNumberUpperBound: upperBound,
            markerTotalCount: totalCount,
        )
    }

    private func fixedUUID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}

@testable import ShotMarker
import XCTest

@MainActor
final class MarkerLabelPlacementTests: XCTestCase {
    func testValidationPreservesPreciseSavedValuesAndNormalizesOnlyUIInput() throws {
        let precise = MarkerLabelPlacement(fontSizeRatio: 0.1234567, normalizedCenterX: 0.1234567, normalizedCenterY: 0.7654321)
        XCTAssertTrue(precise.isValid)
        XCTAssertEqual(try JSONDecoder().decode(MarkerLabelPlacement.self, from: JSONEncoder().encode(precise)), precise)
        let outside = MarkerLabelPlacement(fontSizeRatio: 0.4, normalizedCenterX: -1, normalizedCenterY: .infinity)
        XCTAssertFalse(outside.isValid)
        XCTAssertEqual(outside.normalized, MarkerLabelPlacement(fontSizeRatio: 0.16, normalizedCenterX: 0, normalizedCenterY: 0.1))
        let source = MarkerLabelStyle(fontSizeRatio: 0.1, normalizedCenterX: 0.1, normalizedCenterY: 0.1, textOpacity: 0.2, backgroundOpacity: 0.4)
        let applied = precise.applying(to: source)
        XCTAssertEqual(applied.fontSizeRatio, 0.1234567)
        XCTAssertEqual(applied.textOpacity, 0.2)
        XCTAssertEqual(applied.backgroundOpacity, 0.4)
    }

    func testEveryLayoutFieldRejectsInvalidValuesAndAbsentOverrideIsOmitted() throws {
        for placement in [
            MarkerLabelPlacement(fontSizeRatio: .nan, normalizedCenterX: 0.5, normalizedCenterY: 0.5),
            MarkerLabelPlacement(fontSizeRatio: .infinity, normalizedCenterX: 0.5, normalizedCenterY: 0.5),
            MarkerLabelPlacement(fontSizeRatio: 0.03, normalizedCenterX: 0.5, normalizedCenterY: 0.5),
            MarkerLabelPlacement(fontSizeRatio: 0.1, normalizedCenterX: .nan, normalizedCenterY: 0.5),
            MarkerLabelPlacement(fontSizeRatio: 0.1, normalizedCenterX: 1.1, normalizedCenterY: 0.5),
            MarkerLabelPlacement(fontSizeRatio: 0.1, normalizedCenterX: 0.5, normalizedCenterY: -0.1),
        ] { XCTAssertFalse(placement.isValid) }
        let task = try HighlightTaskTestFixture.task()
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task.reviewItems[0])) as? [String: Any])
        XCTAssertNil(values["markerLabelPlacement"])
        var draft = try HighlightTaskPlanner.reviewDraft(for: task)
        draft.items[0].isIncluded = false
        draft.items[0].markerLabelPlacement = MarkerLabelPlacement(fontSizeRatio: 0.17, normalizedCenterX: 0.5, normalizedCenterY: 0.5)
        XCTAssertThrowsError(try HighlightClipReviewPlanner.makeSummary(items: draft.items, videos: task.videos.map(\.selectedTrainingVideo)))
    }

    func testEqualEffectivePlacementsMergeAndDifferentPlacementsKeepOverlappingRangesComplete() throws {
        let task = try HighlightTaskTestFixture.task()
        var items = try HighlightTaskPlanner.reviewDraft(for: task).items
        items[0].start = 5
        items[0].duration = 10
        items[1].start = 5
        items[1].duration = 10
        var style = MarkerLabelStyle.default
        style.fontSizeRatio = 0.04
        items[1].markerLabelPlacement = MarkerLabelPlacement(style: style)
        let videos = task.videos.map(\.selectedTrainingVideo)
        let merged = try HighlightClipReviewPlanner.makeSummary(items: items, videos: videos, markerLabelStyle: style)
        XCTAssertEqual(merged.finalSegments.count, 1)
        XCTAssertEqual(merged.totalDuration, 10)
        XCTAssertEqual(merged.finalSegments[0].markerLabelPlacement?.fontSizeRatio, 0.04)
        items[1].markerLabelPlacement = MarkerLabelPlacement(fontSizeRatio: 0.16, normalizedCenterX: 0.8, normalizedCenterY: 0.7)
        let split = try HighlightClipReviewPlanner.makeSummary(items: items, videos: videos, markerLabelStyle: style)
        XCTAssertEqual(split.finalSegments.count, 2)
        XCTAssertEqual(split.finalSegments.map(\.start), [5, 5])
        XCTAssertEqual(split.totalDuration, 20)
        let context = HighlightClipReviewContext(items: items, workingItem: items[0], videos: videos, markerLabelStyle: style)
        XCTAssertTrue(context.relationships[0].hasDifferentMarkerLabelPlacement)
        XCTAssertFalse(context.relationships[0].willMerge)
    }

    func testLegacySegmentMissingPlacementKeepsNilForExecutionStyleFallbackAndNullIsRejected() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","videoID":"a","markerIDs":[],"start":0,"duration":2,"markerNumberLowerBound":1,"markerNumberUpperBound":1,"markerTotalCount":1}"#
        let segment = try JSONDecoder().decode(ConfirmedHighlightSegment.self, from: Data(json.utf8))
        XCTAssertNil(segment.markerLabelPlacement)
        var values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        values["markerLabelPlacement"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(ConfirmedHighlightSegment.self, from: JSONSerialization.data(withJSONObject: values)))
    }
}

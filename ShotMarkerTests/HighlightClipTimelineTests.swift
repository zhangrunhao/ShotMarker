@testable import ShotMarker
import XCTest

final class HighlightClipTimelineTests: XCTestCase {
    func testWindowUsesTwentySecondsForShortClipAndCentersFiveOrMoreSecondsOfContext() {
        let window = HighlightClipTimelineGeometry.makeWindow(
            range: HighlightClipRange(start: 20, duration: 4),
            videoDuration: 60,
        )

        XCTAssertEqual(window, HighlightClipTimelineWindow(start: 12, duration: 20))
    }

    func testWindowUsesClipLengthPlusTenSecondsForLongClip() {
        let window = HighlightClipTimelineGeometry.makeWindow(
            range: HighlightClipRange(start: 20, duration: 14),
            videoDuration: 60,
        )

        XCTAssertEqual(window, HighlightClipTimelineWindow(start: 15, duration: 24))
    }

    func testWindowTransfersUnavailableContextAtVideoEdges() {
        XCTAssertEqual(
            HighlightClipTimelineGeometry.makeWindow(
                range: .init(start: 1, duration: 4),
                videoDuration: 60,
            ),
            HighlightClipTimelineWindow(start: 0, duration: 20),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.makeWindow(
                range: .init(start: 55, duration: 4),
                videoDuration: 60,
            ),
            HighlightClipTimelineWindow(start: 40, duration: 20),
        )
    }

    func testVideoShorterThanTargetWindowShowsCompleteVideo() {
        XCTAssertEqual(
            HighlightClipTimelineGeometry.makeWindow(
                range: .init(start: 2, duration: 4),
                videoDuration: 8,
            ),
            HighlightClipTimelineWindow(start: 0, duration: 8),
        )
    }

    func testTimeAndXMappingClampToWindowBounds() {
        let window = HighlightClipTimelineWindow(start: 10, duration: 20)

        XCTAssertEqual(
            HighlightClipTimelineGeometry.x(for: 20, window: window, width: 200),
            100,
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.time(forX: 50, window: window, width: 200),
            15,
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.time(forX: -20, window: window, width: 200),
            10,
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.time(forX: 240, window: window, width: 200),
            30,
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.x(for: 40, window: window, width: 200),
            200,
        )
    }

    func testEachDragRoleProducesOnlyItsOwnAction() {
        let window = HighlightClipTimelineWindow(start: 0, duration: 20)
        let range = HighlightClipRange(start: 5, duration: 4)

        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .startHandle,
                translationX: 20,
                range: range,
                playhead: 5,
                window: window,
                width: 200,
            ),
            .setStart(7),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .endHandle,
                translationX: 20,
                range: range,
                playhead: 5,
                window: window,
                width: 200,
            ),
            .setEnd(11),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .moveRange,
                translationX: 20,
                range: range,
                playhead: 5,
                window: window,
                width: 200,
            ),
            .moveBy(2),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .playhead,
                translationX: 20,
                range: range,
                playhead: 5,
                window: window,
                width: 200,
            ),
            .preview(7),
        )
    }

    func testShiftedWindowFollowsRangeNearEitherEdgeAndStaysInsideVideo() {
        let original = HighlightClipTimelineWindow(start: 0, duration: 20)
        let shiftedRight = HighlightClipTimelineGeometry.shiftedWindow(
            original,
            toContain: .init(start: 18, duration: 4),
            videoDuration: 60,
        )
        XCTAssertEqual(shiftedRight, .init(start: 4, duration: 20))

        let shiftedLeft = HighlightClipTimelineGeometry.shiftedWindow(
            shiftedRight,
            toContain: .init(start: 1, duration: 4),
            videoDuration: 60,
        )
        XCTAssertEqual(shiftedLeft, .init(start: 0, duration: 20))

        let shiftedAtEnd = HighlightClipTimelineGeometry.shiftedWindow(
            original,
            toContain: .init(start: 58, duration: 2),
            videoDuration: 60,
        )
        XCTAssertEqual(shiftedAtEnd, .init(start: 40, duration: 20))
    }

    func testInvalidGeometryProducesFiniteUnchangedActions() {
        let window = HighlightClipTimelineWindow(start: 10, duration: .nan)
        let range = HighlightClipRange(start: 12, duration: 4)

        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .startHandle,
                translationX: .infinity,
                range: range,
                playhead: 13,
                window: window,
                width: 0,
            ),
            .setStart(12),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .endHandle,
                translationX: .nan,
                range: range,
                playhead: 13,
                window: window,
                width: .infinity,
            ),
            .setEnd(16),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .moveRange,
                translationX: 10,
                range: range,
                playhead: 13,
                window: window,
                width: 0,
            ),
            .moveBy(0),
        )
        XCTAssertEqual(
            HighlightClipTimelineGeometry.action(
                for: .playhead,
                translationX: 10,
                range: range,
                playhead: 13,
                window: window,
                width: 0,
            ),
            .preview(13),
        )
    }
}

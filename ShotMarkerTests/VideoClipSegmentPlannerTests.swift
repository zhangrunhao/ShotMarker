@testable import ShotMarker
import XCTest

final class VideoClipSegmentPlannerTests: XCTestCase {
    func testTestClipSegmentsUseBeginningAndMiddleWhenVideoIsLongEnough() {
        let segments = VideoClipSegmentPlanner.testSegments(forDuration: 12, segmentDuration: 2)

        XCTAssertEqual(segments, [
            VideoClipSegment(start: 0, duration: 2),
            VideoClipSegment(start: 5, duration: 2),
        ])
    }

    func testTestClipSegmentsClampToAvailableDurationWhenVideoIsShort() {
        let segments = VideoClipSegmentPlanner.testSegments(forDuration: 3, segmentDuration: 2)

        XCTAssertEqual(segments, [
            VideoClipSegment(start: 0, duration: 1.5),
            VideoClipSegment(start: 1.5, duration: 1.5),
        ])
    }

    func testTestClipSegmentsReturnNoSegmentsWhenVideoHasNoDuration() {
        XCTAssertEqual(VideoClipSegmentPlanner.testSegments(forDuration: 0, segmentDuration: 2), [])
    }
}

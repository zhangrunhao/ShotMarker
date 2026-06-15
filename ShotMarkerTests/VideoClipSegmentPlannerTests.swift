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

    func testHighlightPlanMatchesMarkersAcrossMultipleSelectedVideos() throws {
        let firstMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001001")),
            markedAt: Date(timeIntervalSince1970: 120),
        )
        let secondMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001002")),
            markedAt: Date(timeIntervalSince1970: 240),
        )
        let unmatchedMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001003")),
            markedAt: Date(timeIntervalSince1970: 400),
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 420),
            events: [
                unmatchedMarker,
                secondMarker,
                firstMarker,
            ],
        )
        let firstVideo = SelectedTrainingVideo(
            id: "video-1",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let secondVideo = SelectedTrainingVideo(
            id: "video-2",
            recordedStartAt: Date(timeIntervalSince1970: 220),
            duration: 40,
        )

        let plan = VideoClipSegmentPlanner.highlightPlan(
            for: session,
            videos: [firstVideo, secondVideo],
            clipSettings: ClipSettings(secondsBeforeMarker: 10, secondsAfterMarker: 3),
        )

        XCTAssertEqual(plan.selectedVideoCount, 2)
        XCTAssertEqual(plan.totalMarkerCount, 3)
        XCTAssertEqual(plan.matchedMarkerCount, 2)
        XCTAssertEqual(plan.unmatchedMarkerCount, 1)
        XCTAssertEqual(plan.segments.map(\.markerLabel), ["1/2", "2/2"])
        XCTAssertEqual(plan.segments, [
            HighlightClipSegment(
                markerID: firstMarker.id,
                videoID: firstVideo.id,
                markerAt: firstMarker.markedAt,
                start: 10,
                duration: 13,
                markerNumber: 1,
                markerTotalCount: 2,
            ),
            HighlightClipSegment(
                markerID: secondMarker.id,
                videoID: secondVideo.id,
                markerAt: secondMarker.markedAt,
                start: 10,
                duration: 13,
                markerNumber: 2,
                markerTotalCount: 2,
            ),
        ])
    }

    func testHighlightPlanMergesOverlappingSegmentsAndUsesMarkerRangeLabel() throws {
        let firstMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001301")),
            markedAt: Date(timeIntervalSince1970: 110),
        )
        let secondMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001302")),
            markedAt: Date(timeIntervalSince1970: 114),
        )
        let video = SelectedTrainingVideo(
            id: "video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            events: [secondMarker, firstMarker],
        )

        let plan = VideoClipSegmentPlanner.highlightPlan(
            for: session,
            videos: [video],
            clipSettings: ClipSettings(secondsBeforeMarker: 6, secondsAfterMarker: 2),
        )

        XCTAssertEqual(plan.matchedMarkerCount, 2)
        XCTAssertEqual(plan.unmatchedMarkerCount, 0)
        XCTAssertEqual(plan.segments.first?.markerLabel, "1-2/2")
        XCTAssertEqual(plan.segments.first?.coveredMarkerCount, 2)
        XCTAssertEqual(plan.segments, [
            HighlightClipSegment(
                markerID: firstMarker.id,
                videoID: video.id,
                markerAt: firstMarker.markedAt,
                start: 4,
                duration: 12,
                markerNumberRange: 1...2,
                markerTotalCount: 2,
            ),
        ])
    }

    func testHighlightPlanMergesSegmentsSeparatedByOneSecondGap() throws {
        let firstMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001601")),
            markedAt: Date(timeIntervalSince1970: 110),
        )
        let secondMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001602")),
            markedAt: Date(timeIntervalSince1970: 117),
        )
        let video = SelectedTrainingVideo(
            id: "video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            events: [secondMarker, firstMarker],
        )

        let plan = VideoClipSegmentPlanner.highlightPlan(
            for: session,
            videos: [video],
            clipSettings: ClipSettings(secondsBeforeMarker: 4, secondsAfterMarker: 2),
        )

        XCTAssertEqual(plan.matchedMarkerCount, 2)
        XCTAssertEqual(plan.segments.map(\.markerLabel), ["1-2/2"])
        XCTAssertEqual(plan.segments, [
            HighlightClipSegment(
                markerID: firstMarker.id,
                videoID: video.id,
                markerAt: firstMarker.markedAt,
                start: 6,
                duration: 13,
                markerNumberRange: 1...2,
                markerTotalCount: 2,
            ),
        ])
    }

    func testHighlightPlanDefaultWindowUsesNineSecondsBeforeAndFourSecondsAfterMarker() throws {
        let marker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001401")),
            markedAt: Date(timeIntervalSince1970: 110),
        )
        let video = SelectedTrainingVideo(
            id: "video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            events: [marker],
        )

        let plan = VideoClipSegmentPlanner.highlightPlan(for: session, videos: [video])

        XCTAssertEqual(plan.segments.first?.start, 1)
        XCTAssertEqual(plan.segments.first?.duration, 13)
    }

    func testHighlightPlanClipsSegmentsToVideoBoundaries() throws {
        let startMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001101")),
            markedAt: Date(timeIntervalSince1970: 105),
        )
        let endMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001102")),
            markedAt: Date(timeIntervalSince1970: 155),
        )
        let video = SelectedTrainingVideo(
            id: "video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            events: [endMarker, startMarker],
        )

        let plan = VideoClipSegmentPlanner.highlightPlan(
            for: session,
            videos: [video],
            clipSettings: ClipSettings(secondsBeforeMarker: 10, secondsAfterMarker: 10),
        )

        XCTAssertEqual(plan.segments.map(\.start), [0, 45])
        XCTAssertEqual(plan.segments.map(\.duration), [15, 15])
    }

    func testHighlightPlanUsesSelectionOrderWhenVideosOverlap() throws {
        let marker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001201")),
            markedAt: Date(timeIntervalSince1970: 130),
        )
        let firstSelectedVideo = SelectedTrainingVideo(
            id: "first-selected",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
        let secondSelectedVideo = SelectedTrainingVideo(
            id: "second-selected",
            recordedStartAt: Date(timeIntervalSince1970: 90),
            duration: 80,
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            events: [marker],
        )

        let plan = VideoClipSegmentPlanner.highlightPlan(
            for: session,
            videos: [firstSelectedVideo, secondSelectedVideo],
        )

        XCTAssertEqual(plan.segments.first?.videoID, firstSelectedVideo.id)
    }

    func testCanUseVideoReturnsTrueWhenVideoCoversMarker() throws {
        let marker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001501")),
            markedAt: Date(timeIntervalSince1970: 120),
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            events: [marker],
        )
        let video = SelectedTrainingVideo(
            id: "video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        XCTAssertTrue(VideoClipSegmentPlanner.canUseVideo(video, for: session))
    }

    func testCanUseVideoReturnsFalseWhenVideoCoversNoMarkers() throws {
        let marker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001502")),
            markedAt: Date(timeIntervalSince1970: 200),
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 180),
            endedAt: Date(timeIntervalSince1970: 220),
            events: [marker],
        )
        let video = SelectedTrainingVideo(
            id: "video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        XCTAssertFalse(VideoClipSegmentPlanner.canUseVideo(video, for: session))
    }

    func testCanUseVideoTreatsBoundaryMarkersAsCovered() throws {
        let startMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001503")),
            markedAt: Date(timeIntervalSince1970: 100),
        )
        let endMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001504")),
            markedAt: Date(timeIntervalSince1970: 160),
        )
        let video = SelectedTrainingVideo(
            id: "video",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        let startSession = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 90),
            endedAt: Date(timeIntervalSince1970: 110),
            events: [startMarker],
        )
        let endSession = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 150),
            endedAt: Date(timeIntervalSince1970: 170),
            events: [endMarker],
        )

        XCTAssertTrue(VideoClipSegmentPlanner.canUseVideo(video, for: startSession))
        XCTAssertTrue(VideoClipSegmentPlanner.canUseVideo(video, for: endSession))
    }

    func testCanUseVideoReturnsFalseForInvalidDuration() throws {
        let marker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000001505")),
            markedAt: Date(timeIntervalSince1970: 100),
        )
        let session = TrainingSession(
            startedAt: Date(timeIntervalSince1970: 90),
            endedAt: Date(timeIntervalSince1970: 110),
            events: [marker],
        )
        let zeroDurationVideo = SelectedTrainingVideo(
            id: "zero",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 0,
        )
        let infiniteDurationVideo = SelectedTrainingVideo(
            id: "infinite",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: .infinity,
        )

        XCTAssertFalse(VideoClipSegmentPlanner.canUseVideo(zeroDurationVideo, for: session))
        XCTAssertFalse(VideoClipSegmentPlanner.canUseVideo(infiniteDurationVideo, for: session))
    }
}

import Foundation

struct VideoClipSegment: Equatable {
    let start: TimeInterval
    let duration: TimeInterval
}

enum VideoClipSegmentPlanner {
    static func testSegments(
        forDuration videoDuration: TimeInterval,
        segmentDuration requestedSegmentDuration: TimeInterval = 2,
    ) -> [VideoClipSegment] {
        guard videoDuration > 0, requestedSegmentDuration > 0 else {
            return []
        }

        let totalRequestedDuration = requestedSegmentDuration * 2
        guard videoDuration > totalRequestedDuration else {
            let duration = videoDuration / 2
            return [
                VideoClipSegment(start: 0, duration: duration),
                VideoClipSegment(start: duration, duration: duration),
            ]
        }

        return [
            VideoClipSegment(start: 0, duration: requestedSegmentDuration),
            VideoClipSegment(
                start: (videoDuration - requestedSegmentDuration) / 2,
                duration: requestedSegmentDuration,
            ),
        ]
    }
}

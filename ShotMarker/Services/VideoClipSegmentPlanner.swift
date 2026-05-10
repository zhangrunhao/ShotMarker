import Foundation

struct VideoClipSegment: Equatable {
    let start: TimeInterval
    let duration: TimeInterval
}

struct SelectedTrainingVideo: Identifiable, Equatable {
    let id: String
    let recordedStartAt: Date
    let duration: TimeInterval

    var recordedEndAt: Date {
        recordedStartAt.addingTimeInterval(duration)
    }
}

struct HighlightClipSegment: Equatable {
    let markerID: UUID
    let videoID: String
    let markerAt: Date
    let start: TimeInterval
    let duration: TimeInterval
    let markerNumberRange: ClosedRange<Int>
    let markerTotalCount: Int

    init(
        markerID: UUID,
        videoID: String,
        markerAt: Date,
        start: TimeInterval,
        duration: TimeInterval,
        markerNumber: Int = 1,
        markerTotalCount: Int = 1,
    ) {
        self.init(
            markerID: markerID,
            videoID: videoID,
            markerAt: markerAt,
            start: start,
            duration: duration,
            markerNumberRange: markerNumber...markerNumber,
            markerTotalCount: markerTotalCount,
        )
    }

    init(
        markerID: UUID,
        videoID: String,
        markerAt: Date,
        start: TimeInterval,
        duration: TimeInterval,
        markerNumberRange: ClosedRange<Int>,
        markerTotalCount: Int,
    ) {
        self.markerID = markerID
        self.videoID = videoID
        self.markerAt = markerAt
        self.start = start
        self.duration = duration
        self.markerNumberRange = markerNumberRange
        self.markerTotalCount = markerTotalCount
    }

    var coveredMarkerCount: Int {
        markerNumberRange.upperBound - markerNumberRange.lowerBound + 1
    }

    var markerLabel: String {
        if markerNumberRange.lowerBound == markerNumberRange.upperBound {
            return "\(markerNumberRange.lowerBound)/\(markerTotalCount)"
        }

        return "\(markerNumberRange.lowerBound)-\(markerNumberRange.upperBound)/\(markerTotalCount)"
    }
}

struct HighlightClipPlan: Equatable {
    let selectedVideoCount: Int
    let totalMarkerCount: Int
    let matchedMarkerCount: Int
    let segments: [HighlightClipSegment]

    var unmatchedMarkerCount: Int {
        totalMarkerCount - matchedMarkerCount
    }

    var canGenerate: Bool {
        matchedMarkerCount > 0
    }
}

enum VideoClipSegmentPlanner {
    private static let segmentMergeGapTolerance: TimeInterval = 1

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

    static func highlightPlan(
        for session: TrainingSession,
        videos: [SelectedTrainingVideo],
        clipSettings: ClipSettings = .default,
    ) -> HighlightClipPlan {
        let events = session.events.sorted { $0.markedAt < $1.markedAt }
        let matchingSegments = events.compactMap { event in
            highlightSegment(
                for: event,
                videos: videos,
                clipSettings: clipSettings,
            )
        }
        let plannedSegments = matchingSegments.enumerated().map { index, segment in
            segment.numbered(markerNumber: index + 1, markerTotalCount: matchingSegments.count)
        }
        let mergedSegments = mergeOverlappingSegments(plannedSegments)

        return HighlightClipPlan(
            selectedVideoCount: videos.count,
            totalMarkerCount: events.count,
            matchedMarkerCount: plannedSegments.count,
            segments: mergedSegments,
        )
    }

    private static func mergeOverlappingSegments(
        _ segments: [HighlightClipSegment],
    ) -> [HighlightClipSegment] {
        segments.reduce(into: []) { mergedSegments, segment in
            guard let previousSegment = mergedSegments.last,
                  previousSegment.videoID == segment.videoID,
                  segment.start <= previousSegment.end + segmentMergeGapTolerance
            else {
                mergedSegments.append(segment)
                return
            }

            mergedSegments[mergedSegments.count - 1] = previousSegment.merged(with: segment)
        }
    }

    private static func highlightSegment(
        for event: ShotMarkerEvent,
        videos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
    ) -> HighlightClipSegment? {
        guard let video = videos.first(where: { video in
            video.recordedStartAt <= event.markedAt && event.markedAt <= video.recordedEndAt
        }) else {
            return nil
        }

        let desiredStartAt = event.markedAt.addingTimeInterval(-clipSettings.secondsBeforeMarker)
        let desiredEndAt = event.markedAt.addingTimeInterval(clipSettings.secondsAfterMarker)
        let clippedStartAt = max(desiredStartAt, video.recordedStartAt)
        let clippedEndAt = min(desiredEndAt, video.recordedEndAt)
        let duration = clippedEndAt.timeIntervalSince(clippedStartAt)

        guard duration > 0 else {
            return nil
        }

        return HighlightClipSegment(
            markerID: event.id,
            videoID: video.id,
            markerAt: event.markedAt,
            start: clippedStartAt.timeIntervalSince(video.recordedStartAt),
            duration: duration,
        )
    }
}

private extension HighlightClipSegment {
    var end: TimeInterval {
        start + duration
    }

    func numbered(markerNumber: Int, markerTotalCount: Int) -> HighlightClipSegment {
        HighlightClipSegment(
            markerID: markerID,
            videoID: videoID,
            markerAt: markerAt,
            start: start,
            duration: duration,
            markerNumber: markerNumber,
            markerTotalCount: markerTotalCount,
        )
    }

    func merged(with segment: HighlightClipSegment) -> HighlightClipSegment {
        let mergedStart = min(start, segment.start)
        let mergedEnd = max(end, segment.end)
        let mergedNumberRange = min(markerNumberRange.lowerBound, segment.markerNumberRange.lowerBound)
            ... max(markerNumberRange.upperBound, segment.markerNumberRange.upperBound)

        return HighlightClipSegment(
            markerID: markerID,
            videoID: videoID,
            markerAt: markerAt,
            start: mergedStart,
            duration: mergedEnd - mergedStart,
            markerNumberRange: mergedNumberRange,
            markerTotalCount: markerTotalCount,
        )
    }
}

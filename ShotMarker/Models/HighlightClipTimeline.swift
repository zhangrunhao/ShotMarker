import Foundation

struct HighlightClipTimelineWindow: Equatable {
    let start: TimeInterval
    let duration: TimeInterval

    var end: TimeInterval {
        start + duration
    }
}

enum HighlightClipTimelineRole: Equatable {
    case startHandle
    case endHandle
    case moveRange
    case playhead
}

enum HighlightClipTimelineAction: Equatable {
    case setStart(TimeInterval)
    case setEnd(TimeInterval)
    case moveBy(TimeInterval)
    case preview(TimeInterval)
}

enum HighlightClipTimelineGeometry {
    static func makeWindow(
        range: HighlightClipRange,
        videoDuration: TimeInterval,
    ) -> HighlightClipTimelineWindow {
        guard videoDuration.isFinite, videoDuration > 0 else {
            return HighlightClipTimelineWindow(start: 0, duration: 0)
        }

        let rangeDuration = range.duration.isFinite ? max(range.duration, 0) : 0
        let targetDuration = min(videoDuration, max(rangeDuration + 10, 20))
        let rangeStart = range.start.isFinite ? range.start : 0
        let centeredStart = rangeStart + rangeDuration / 2 - targetDuration / 2
        let maximumStart = max(videoDuration - targetDuration, 0)
        let start = min(max(centeredStart, 0), maximumStart)
        return HighlightClipTimelineWindow(start: start, duration: targetDuration)
    }

    static func shiftedWindow(
        _ window: HighlightClipTimelineWindow,
        toContain range: HighlightClipRange,
        videoDuration: TimeInterval,
    ) -> HighlightClipTimelineWindow {
        guard videoDuration.isFinite,
              videoDuration > 0,
              window.duration.isFinite,
              window.duration > 0,
              range.start.isFinite,
              range.duration.isFinite,
              range.duration > 0,
              range.end.isFinite
        else {
            return window
        }

        let duration = min(window.duration, videoDuration)
        let maximumStart = max(videoDuration - duration, 0)
        var start = min(max(window.start.isFinite ? window.start : 0, 0), maximumStart)
        let context = min(2, max((duration - range.duration) / 2, 0))

        if range.start < start + context {
            start = range.start - context
        } else if range.end > start + duration - context {
            start = range.end + context - duration
        }

        start = min(max(start, 0), maximumStart)
        return HighlightClipTimelineWindow(start: start, duration: duration)
    }

    static func x(
        for time: TimeInterval,
        window: HighlightClipTimelineWindow,
        width: Double,
    ) -> Double {
        guard time.isFinite,
              width.isFinite,
              width > 0,
              window.start.isFinite,
              window.duration.isFinite,
              window.duration > 0,
              window.end.isFinite
        else {
            return 0
        }

        let clampedTime = min(max(time, window.start), window.end)
        return (clampedTime - window.start) / window.duration * width
    }

    static func time(
        forX x: Double,
        window: HighlightClipTimelineWindow,
        width: Double,
    ) -> TimeInterval {
        guard x.isFinite,
              width.isFinite,
              width > 0,
              window.start.isFinite,
              window.duration.isFinite,
              window.duration > 0,
              window.end.isFinite
        else {
            return window.start.isFinite ? window.start : 0
        }

        let clampedX = min(max(x, 0), width)
        let mappedTime = window.start + clampedX / width * window.duration
        return min(max(mappedTime, window.start), window.end)
    }

    static func action(
        for role: HighlightClipTimelineRole,
        translationX: Double,
        range: HighlightClipRange,
        playhead: TimeInterval,
        window: HighlightClipTimelineWindow,
        width: Double,
    ) -> HighlightClipTimelineAction {
        guard translationX.isFinite,
              width.isFinite,
              width > 0,
              window.duration.isFinite,
              window.duration > 0
        else {
            return unchangedAction(for: role, range: range, playhead: playhead)
        }

        let delta = translationX * window.duration / width
        guard delta.isFinite else {
            return unchangedAction(for: role, range: range, playhead: playhead)
        }

        switch role {
        case .startHandle:
            return .setStart(range.start + delta)
        case .endHandle:
            return .setEnd(range.end + delta)
        case .moveRange:
            return .moveBy(delta)
        case .playhead:
            return .preview(playhead + delta)
        }
    }

    private static func unchangedAction(
        for role: HighlightClipTimelineRole,
        range: HighlightClipRange,
        playhead: TimeInterval,
    ) -> HighlightClipTimelineAction {
        switch role {
        case .startHandle:
            return .setStart(range.start)
        case .endHandle:
            return .setEnd(range.end)
        case .moveRange:
            return .moveBy(0)
        case .playhead:
            return .preview(playhead)
        }
    }
}

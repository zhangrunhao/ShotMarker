import CoreMedia
import Foundation

enum HighlightClipReviewPlanner {
    static let exportTimescale: CMTimeScale = 600
    private static let tenthSecondTicks: CMTimeValue = 60
    static let mergeGapTolerance: TimeInterval = 1

    static func normalizedTenths(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else {
            return seconds
        }

        let time = CMTime(seconds: seconds, preferredTimescale: exportTimescale)
        let tenths = (Double(time.value) / Double(tenthSecondTicks))
            .rounded(.toNearestOrAwayFromZero)
        return CMTime(
            value: CMTimeValue(tenths) * tenthSecondTicks,
            timescale: exportTimescale,
        ).seconds
    }

    static func apply(
        _ edit: HighlightClipRangeEdit,
        to item: HighlightClipReviewItem,
        videoDuration: TimeInterval,
    ) throws -> HighlightClipReviewItem {
        guard videoDuration.isFinite, videoDuration > 0 else {
            throw HighlightClipReviewPlanningError.invalidRange
        }

        _ = try validatedRange(item.range, videoDuration: videoDuration)

        let editValues: [TimeInterval]
        switch edit {
        case .setStart(let start), .setEnd(let start), .moveBy(let start):
            editValues = [start]
        case .replace(let start, let duration):
            editValues = [start, duration]
        }
        guard editValues.allSatisfy(\.isFinite) else {
            throw HighlightClipReviewPlanningError.invalidRange
        }

        var editedItem = item
        guard videoDuration >= 1 else {
            editedItem.start = 0
            editedItem.duration = videoDuration
            return editedItem
        }

        let minimumDuration: TimeInterval = 1
        switch edit {
        case .setStart(let requestedStart):
            let end = item.range.end
            let start = min(
                max(normalizedTenths(requestedStart), 0),
                end - minimumDuration,
            )
            editedItem.start = start
            editedItem.duration = end - start
        case .setEnd(let requestedEnd):
            let end = min(
                max(normalizedTenths(requestedEnd), item.start + minimumDuration),
                videoDuration,
            )
            editedItem.duration = end - item.start
        case .moveBy(let requestedDelta):
            let delta = normalizedTenths(requestedDelta)
            let start = normalizedTenths(item.start + delta)
            editedItem.start = min(max(start, 0), videoDuration - item.duration)
        case .replace(let requestedStart, let requestedDuration):
            let duration = min(
                max(normalizedTenths(requestedDuration), minimumDuration),
                videoDuration,
            )
            let start = min(
                max(normalizedTenths(requestedStart), 0),
                videoDuration - duration,
            )
            editedItem.start = start
            editedItem.duration = duration
        }

        _ = try validatedRange(editedItem.range, videoDuration: videoDuration)
        return editedItem
    }

    static func validatedRange(
        _ range: HighlightClipRange,
        videoDuration: TimeInterval,
    ) throws -> HighlightClipRange {
        guard videoDuration.isFinite,
              videoDuration > 0,
              range.start.isFinite,
              range.duration.isFinite,
              range.start >= 0,
              range.duration > 0,
              range.end <= videoDuration,
              range.duration >= min(1, videoDuration)
        else {
            throw HighlightClipReviewPlanningError.invalidRange
        }

        return range
    }
}

enum HighlightClipReviewPlanningError: LocalizedError, Equatable {
    case emptySelection
    case sourceVideoMissing
    case invalidRange
    case missingMarkers
    case inconsistentNumbering
    case duplicateIdentity

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "至少需要保留一个可用片段。"
        case .sourceVideoMissing:
            "找不到片段使用的视频，请重新选择视频。"
        case .invalidRange:
            "片段范围无效，请恢复默认范围后再试。"
        case .missingMarkers:
            "片段缺少关联打点，请重新创建任务。"
        case .inconsistentNumbering:
            "片段编号数据无效，请重新创建任务。"
        case .duplicateIdentity:
            "片段数据重复，请重新创建任务。"
        }
    }
}

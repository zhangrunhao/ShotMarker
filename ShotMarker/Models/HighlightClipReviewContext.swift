import Foundation

struct HighlightClipNeighborRelationship: Equatable, Identifiable {
    enum Position: Equatable {
        case previous
        case next
    }

    enum Separation: Equatable {
        case overlap(seconds: TimeInterval)
        case gap(seconds: TimeInterval)
        case differentVideo
    }

    let itemID: UUID
    let position: Position
    let candidateNumber: Int
    let range: HighlightClipRange
    let isIncluded: Bool
    let separation: Separation
    let willMerge: Bool

    var id: UUID {
        itemID
    }

    var timelineRange: HighlightClipRange? {
        separation == .differentVideo ? nil : range
    }
}

struct HighlightClipReviewContext {
    let candidateNumber: Int?
    let candidateCount: Int
    let previousItem: HighlightClipReviewItem?
    let nextItem: HighlightClipReviewItem?
    let relationships: [HighlightClipNeighborRelationship]

    init(
        items: [HighlightClipReviewItem],
        workingItem: HighlightClipReviewItem,
        videos: [SelectedTrainingVideo],
    ) {
        candidateCount = items.count
        guard let index = items.firstIndex(where: { $0.id == workingItem.id }) else {
            candidateNumber = nil
            previousItem = nil
            nextItem = nil
            relationships = []
            return
        }

        candidateNumber = index + 1
        previousItem = index > items.startIndex ? items[index - 1] : nil
        nextItem = index + 1 < items.endIndex ? items[index + 1] : nil

        var workingItems = items
        workingItems[index] = workingItem
        let summary = try? HighlightClipReviewPlanner.makeSummary(items: workingItems, videos: videos)
        let currentSegment = workingItem.markerReferences.first.flatMap { marker in
            summary?.finalSegments.first { $0.markerIDs.contains(marker.id) }
        }
        let mergedMarkerIDs = Set(currentSegment?.markerIDs ?? [])

        let neighbors: [(Int, HighlightClipNeighborRelationship.Position)] = [
            (index - 1, .previous),
            (index + 1, .next),
        ]
        relationships = neighbors.compactMap { neighborIndex, position in
            guard items.indices.contains(neighborIndex) else {
                return nil
            }

            let neighbor = items[neighborIndex]
            let separation: HighlightClipNeighborRelationship.Separation
            if neighbor.videoID != workingItem.videoID {
                separation = .differentVideo
            } else {
                let sharedDuration = min(workingItem.range.end, neighbor.range.end)
                    - max(workingItem.start, neighbor.start)
                separation = sharedDuration > 0
                    ? .overlap(seconds: sharedDuration)
                    : .gap(seconds: max(0, -sharedDuration))
            }

            // Final segments can include an earlier range that bridges a larger
            // direct neighbor gap, so let the export planner determine membership.
            let willMerge = workingItem.isIncluded && neighbor.isIncluded
                && neighbor.markerReferences.contains { mergedMarkerIDs.contains($0.id) }
            return HighlightClipNeighborRelationship(
                itemID: neighbor.id,
                position: position,
                candidateNumber: neighborIndex + 1,
                range: neighbor.range,
                isIncluded: neighbor.isIncluded,
                separation: separation,
                willMerge: willMerge,
            )
        }
    }
}

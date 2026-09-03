import Foundation

extension HighlightClipReviewPlanner {
    static func restoreDraft(
        for session: TrainingSession,
        videos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
        persistedRecord: PersistedHighlightClipReview?,
    ) -> HighlightClipReviewRestorationResult {
        let completeDraft = makeDraft(
            for: session,
            videos: videos,
            clipSettings: clipSettings,
        )
        guard let persistedRecord else {
            return HighlightClipReviewRestorationResult(
                draft: completeDraft,
                discardedConfirmationCount: 0,
            )
        }

        let flattenedReferences = completeDraft.items
            .flatMap(\.markerReferences)
            .sorted { lhs, rhs in
                if lhs.originalMatchedNumber == rhs.originalMatchedNumber {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.originalMatchedNumber < rhs.originalMatchedNumber
            }
        let referencesByID = flattenedReferences.reduce(
            into: [UUID: HighlightClipMarkerReference](),
        ) { result, reference in
            result[reference.id] = reference
        }
        let eventsByID = session.events.reduce(into: [UUID: ShotMarkerEvent]()) { result, event in
            result[event.id] = event
        }
        let videosByID = videos.reduce(into: [String: SelectedTrainingVideo]()) { result, video in
            result[video.id] = video
        }
        let videoIDByMarkerID = completeDraft.items.reduce(into: [UUID: String]()) { result, item in
            for reference in item.markerReferences {
                result[reference.id] = item.videoID
            }
        }
        let videoIdentitiesByID = videos.reduce(into: [String: HighlightClipReviewVideoIdentity]()) {
            result, video in
            result[video.id] = try? HighlightClipReviewIdentityBuilder.videoIdentity(for: video)
        }

        var occupiedMarkerIDs = Set<UUID>()
        var confirmedItems: [HighlightClipReviewItem] = []
        var discardedConfirmationCount = 0

        for confirmation in persistedRecord.confirmedItems {
            guard let item = restoredItem(
                from: confirmation,
                referencesByID: referencesByID,
                videoIDByMarkerID: videoIDByMarkerID,
                videosByID: videosByID,
                videoIdentitiesByID: videoIdentitiesByID,
                occupiedMarkerIDs: occupiedMarkerIDs,
            ) else {
                discardedConfirmationCount += 1
                continue
            }
            occupiedMarkerIDs.formUnion(confirmation.markerIDs)
            confirmedItems.append(item)
        }

        let defaultItems = defaultItems(
            separatedBy: occupiedMarkerIDs,
            flattenedReferences: flattenedReferences,
            eventsByID: eventsByID,
            session: session,
            videos: videos,
            clipSettings: clipSettings,
            referencesByID: referencesByID,
        )
        let videoIndexes = videos.indices.reduce(into: [String: Int]()) { result, index in
            if result[videos[index].id] == nil {
                result[videos[index].id] = index
            }
        }
        let items = (confirmedItems + defaultItems).sorted { lhs, rhs in
            let lhsNumber = lhs.markerReferences.first?.originalMatchedNumber ?? .max
            let rhsNumber = rhs.markerReferences.first?.originalMatchedNumber ?? .max
            if lhsNumber != rhsNumber {
                return lhsNumber < rhsNumber
            }
            let lhsMarkerID = lhs.markerReferences.first?.id.uuidString ?? ""
            let rhsMarkerID = rhs.markerReferences.first?.id.uuidString ?? ""
            if lhsMarkerID != rhsMarkerID {
                return lhsMarkerID < rhsMarkerID
            }
            return (videoIndexes[lhs.videoID] ?? .max) < (videoIndexes[rhs.videoID] ?? .max)
        }

        return HighlightClipReviewRestorationResult(
            draft: HighlightClipReviewDraft(
                selectedVideoCount: videos.count,
                totalMarkerCount: session.events.count,
                items: items,
            ),
            discardedConfirmationCount: discardedConfirmationCount,
        )
    }

    private static func restoredItem(
        from confirmation: PersistedHighlightClipConfirmation,
        referencesByID: [UUID: HighlightClipMarkerReference],
        videoIDByMarkerID: [UUID: String],
        videosByID: [String: SelectedTrainingVideo],
        videoIdentitiesByID: [String: HighlightClipReviewVideoIdentity],
        occupiedMarkerIDs: Set<UUID>,
    ) -> HighlightClipReviewItem? {
        guard !confirmation.markerIDs.isEmpty,
              Set(confirmation.markerIDs).count == confirmation.markerIDs.count,
              occupiedMarkerIDs.isDisjoint(with: confirmation.markerIDs)
        else {
            return nil
        }

        let references = confirmation.markerIDs.compactMap { referencesByID[$0] }
        guard references.count == confirmation.markerIDs.count else {
            return nil
        }
        let originalNumbers = references.map(\.originalMatchedNumber)
        guard zip(originalNumbers, originalNumbers.dropFirst()).allSatisfy({ lhs, rhs in
            rhs == lhs + 1
        }) else {
            return nil
        }

        let runtimeVideoIDs = Set(confirmation.markerIDs.compactMap { videoIDByMarkerID[$0] })
        guard runtimeVideoIDs.count == 1,
              let runtimeVideoID = runtimeVideoIDs.first,
              let video = videosByID[runtimeVideoID],
              videoIdentitiesByID[runtimeVideoID] == confirmation.videoIdentity,
              isValidPersistedRange(
                  start: confirmation.defaultStart,
                  duration: confirmation.defaultDuration,
                  videoDuration: video.duration,
              ),
              isValidPersistedRange(
                  start: confirmation.start,
                  duration: confirmation.duration,
                  videoDuration: video.duration,
              )
        else {
            return nil
        }

        return HighlightClipReviewItem(
            id: confirmation.markerIDs[0],
            videoID: runtimeVideoID,
            markerReferences: references,
            defaultStart: confirmation.defaultStart,
            defaultDuration: confirmation.defaultDuration,
            start: confirmation.start,
            duration: confirmation.duration,
            isIncluded: confirmation.isIncluded,
            confirmationState: .confirmed,
        )
    }

    private static func isValidPersistedRange(
        start: TimeInterval,
        duration: TimeInterval,
        videoDuration: TimeInterval,
    ) -> Bool {
        guard isNormalizedTenth(start), isNormalizedTenth(duration) else {
            return false
        }
        return (try? validatedRange(
            HighlightClipRange(start: start, duration: duration),
            videoDuration: videoDuration,
        )) != nil
    }

    private static func defaultItems(
        separatedBy occupiedMarkerIDs: Set<UUID>,
        flattenedReferences: [HighlightClipMarkerReference],
        eventsByID: [UUID: ShotMarkerEvent],
        session: TrainingSession,
        videos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
        referencesByID: [UUID: HighlightClipMarkerReference],
    ) -> [HighlightClipReviewItem] {
        var referenceRuns: [[HighlightClipMarkerReference]] = []
        var currentRun: [HighlightClipMarkerReference] = []
        for reference in flattenedReferences {
            if occupiedMarkerIDs.contains(reference.id) {
                if !currentRun.isEmpty {
                    referenceRuns.append(currentRun)
                    currentRun = []
                }
            } else {
                currentRun.append(reference)
            }
        }
        if !currentRun.isEmpty {
            referenceRuns.append(currentRun)
        }

        return referenceRuns.flatMap { run -> [HighlightClipReviewItem] in
            let events = run.compactMap { eventsByID[$0.id] }
            guard events.count == run.count else {
                return []
            }
            let partialDraft = makeDraft(
                for: TrainingSession(
                    id: session.id,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    events: events,
                ),
                videos: videos,
                clipSettings: clipSettings,
            )
            return partialDraft.items.compactMap { item in
                let references = item.markerReferences.compactMap { reference in
                    referencesByID[reference.id]
                }
                guard references.count == item.markerReferences.count else {
                    return nil
                }
                return HighlightClipReviewItem(
                    id: item.id,
                    videoID: item.videoID,
                    markerReferences: references,
                    defaultStart: item.defaultStart,
                    defaultDuration: item.defaultDuration,
                    start: item.start,
                    duration: item.duration,
                    isIncluded: item.isIncluded,
                    confirmationState: .defaultValue,
                )
            }
        }
    }

}

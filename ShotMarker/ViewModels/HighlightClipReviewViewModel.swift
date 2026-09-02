import Combine
import CoreGraphics
import Foundation

enum HighlightClipThumbnailState: Equatable {
    case idle
    case loading
    case loaded(Data)
    case placeholder
}

@MainActor
final class HighlightClipReviewViewModel: ObservableObject {
    typealias SubmitSegments = ([ConfirmedHighlightSegment]) async throws -> Void

    @Published private(set) var items: [HighlightClipReviewItem]
    @Published private(set) var summary: HighlightClipReviewSummary
    @Published private(set) var thumbnailStates: [UUID: HighlightClipThumbnailState]
    @Published private(set) var unavailableItemIDs: Set<UUID> = []
    @Published private(set) var itemErrorMessages: [UUID: String] = [:]
    @Published private(set) var planningErrorMessage: String?
    @Published private(set) var editingItemID: UUID?
    @Published private(set) var isSubmitting = false
    @Published private(set) var submissionErrorMessage: String?

    let mediaProvider: HighlightClipReviewMediaProvider
    private(set) var videos: [SelectedTrainingVideo]

    private let originalItems: [HighlightClipReviewItem]
    private let inputFingerprint: HighlightClipReviewInputFingerprint
    private let submitSegments: SubmitSegments
    private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
    private var thumbnailTargetSizes: [UUID: CGSize] = [:]

    init(
        draft: HighlightClipReviewDraft,
        videos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
        mediaProvider: HighlightClipReviewMediaProvider,
        submitSegments: @escaping SubmitSegments,
    ) {
        items = draft.items
        originalItems = draft.items
        self.videos = videos
        self.mediaProvider = mediaProvider
        self.submitSegments = submitSegments
        inputFingerprint = Self.makeFingerprint(videos: videos, clipSettings: clipSettings)

        let includedMarkerCount = draft.items
            .filter(\.isIncluded)
            .reduce(0) { $0 + $1.markerReferences.count }
        let excludedMarkerCount = draft.items
            .filter { !$0.isIncluded }
            .reduce(0) { $0 + $1.markerReferences.count }
        summary = HighlightClipReviewSummary(
            includedMarkerCount: includedMarkerCount,
            excludedMarkerCount: excludedMarkerCount,
            finalSegments: [],
            displayNumberRangesByItemID: [:],
            mergingItemIDs: [],
        )
        thumbnailStates = draft.items.reduce(into: [:]) { states, item in
            states[item.id] = .idle
        }

        refreshSummary()
    }

    var hasUserChanges: Bool {
        items != originalItems
    }

    var canConfirm: Bool {
        guard !summary.finalSegments.isEmpty,
              planningErrorMessage == nil,
              !isSubmitting
        else {
            return false
        }

        return items.filter(\.isIncluded).allSatisfy { item in
            !unavailableItemIDs.contains(item.id)
                && itemErrorMessages[item.id] == nil
        }
    }

    func setIncluded(_ isIncluded: Bool, itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        items[index].isIncluded = isIncluded
        refreshSummary()
    }

    func apply(_ edit: HighlightClipRangeEdit, itemID: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw HighlightClipReviewPlanningError.missingMarkers
        }
        guard let video = videos.first(where: { $0.id == items[index].videoID }) else {
            let error = HighlightClipReviewPlanningError.sourceVideoMissing
            itemErrorMessages[itemID] = Self.userFacingMessage(for: error)
            throw error
        }

        do {
            items[index] = try HighlightClipReviewPlanner.apply(
                edit,
                to: items[index],
                videoDuration: video.duration,
            )
            itemErrorMessages[itemID] = nil
            refreshSummary()
            scheduleThumbnailRefreshIfNeeded(itemID: itemID)
        } catch {
            itemErrorMessages[itemID] = Self.userFacingMessage(for: error)
            throw error
        }
    }

    func restoreDefault(itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        items[index].start = items[index].defaultStart
        items[index].duration = items[index].defaultDuration
        itemErrorMessages[itemID] = nil
        refreshSummary()
        scheduleThumbnailRefreshIfNeeded(itemID: itemID)
    }

    func loadThumbnail(itemID: UUID, targetSize: CGSize) async {
        guard let task = startThumbnailLoad(itemID: itemID, targetSize: targetSize) else {
            return
        }

        await task.value
    }

    func markSourceUnavailable(itemID: UUID) {
        guard items.contains(where: { $0.id == itemID }) else {
            return
        }

        unavailableItemIDs.insert(itemID)
        itemErrorMessages[itemID] = Self.userFacingMessage(
            for: HighlightClipReviewMediaError.sourceUnavailable,
        )
    }

    func openEditor(itemID: UUID) {
        guard items.contains(where: { $0.id == itemID }) else {
            return
        }

        editingItemID = itemID
    }

    func closeEditor() {
        editingItemID = nil
    }

    func confirmedSegments() throws -> [ConfirmedHighlightSegment] {
        let displayedSegments = summary.finalSegments
        _ = try HighlightClipReviewPlanner.validateConfirmedSegments(
            displayedSegments,
            videos: videos,
            validMarkerIDs: Set(items.flatMap(\.markerReferences).map(\.id)),
        )
        return displayedSegments
    }

    func submit() async {
        guard canConfirm, !isSubmitting else {
            return
        }

        let segments: [ConfirmedHighlightSegment]
        do {
            segments = try confirmedSegments()
        } catch {
            planningErrorMessage = Self.userFacingMessage(for: error)
            return
        }

        isSubmitting = true
        submissionErrorMessage = nil
        defer {
            isSubmitting = false
        }

        do {
            try await submitSegments(segments)
        } catch {
            submissionErrorMessage = Self.userFacingMessage(for: error)
        }
    }

    func requiresInvalidation(
        videos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
    ) -> Bool {
        Self.makeFingerprint(videos: videos, clipSettings: clipSettings) != inputFingerprint
    }

    func cancelMediaLoading() {
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
        mediaProvider.removeAllCachedResources()
    }

    private func refreshSummary() {
        do {
            summary = try HighlightClipReviewPlanner.makeSummary(items: items, videos: videos)
            planningErrorMessage = nil
        } catch {
            planningErrorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func scheduleThumbnailRefreshIfNeeded(itemID: UUID) {
        guard let targetSize = thumbnailTargetSizes[itemID] else {
            return
        }

        _ = startThumbnailLoad(itemID: itemID, targetSize: targetSize)
    }

    @discardableResult
    private func startThumbnailLoad(
        itemID: UUID,
        targetSize: CGSize,
    ) -> Task<Void, Never>? {
        guard let item = items.first(where: { $0.id == itemID }),
              let video = videos.first(where: { $0.id == item.videoID })
        else {
            return nil
        }

        thumbnailTasks[itemID]?.cancel()
        thumbnailTargetSizes[itemID] = targetSize
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await performThumbnailLoad(
                item: item,
                video: video,
                targetSize: targetSize,
            )
        }
        thumbnailTasks[itemID] = task
        return task
    }

    private func performThumbnailLoad(
        item: HighlightClipReviewItem,
        video: SelectedTrainingVideo,
        targetSize: CGSize,
    ) async {
        let previousData: Data?
        if case .loaded(let data) = thumbnailStates[item.id] {
            previousData = data
        } else {
            previousData = nil
            thumbnailStates[item.id] = .loading
        }

        do {
            let data = try await mediaProvider.thumbnailData(
                for: item,
                video: video,
                targetSize: targetSize,
            )
            try Task.checkCancellation()
            thumbnailStates[item.id] = .loaded(data)
            if unavailableItemIDs.remove(item.id) != nil {
                itemErrorMessages[item.id] = nil
            }
        } catch is CancellationError {
            return
        } catch let error as HighlightClipReviewMediaError {
            if error == .sourceUnavailable {
                unavailableItemIDs.insert(item.id)
                itemErrorMessages[item.id] = Self.userFacingMessage(for: error)
            }
            if let previousData {
                thumbnailStates[item.id] = .loaded(previousData)
            } else {
                thumbnailStates[item.id] = .placeholder
            }
        } catch {
            if let previousData {
                thumbnailStates[item.id] = .loaded(previousData)
            } else {
                thumbnailStates[item.id] = .placeholder
            }
        }
    }

    private static func makeFingerprint(
        videos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
    ) -> HighlightClipReviewInputFingerprint {
        let normalizedSettings = clipSettings.normalized
        return HighlightClipReviewInputFingerprint(
            videos: videos,
            secondsBeforeMarker: normalizedSettings.secondsBeforeMarker,
            secondsAfterMarker: normalizedSettings.secondsAfterMarker,
        )
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription
        {
            return description
        }

        return error.localizedDescription
    }
}

import Combine
import Foundation

enum HighlightClipConfirmationNavigation: Equatable {
    case open(itemID: UUID)
    case continueReview(itemID: UUID, sourceVideoID: String, framing: ClipFraming, markerLabelPlacement: MarkerLabelPlacement? = nil)
    case returnToReview
}

@MainActor
final class HighlightClipEditorViewModel: ObservableObject {
    typealias ConfirmWorkingCopy =
        (HighlightClipReviewItem) async throws -> HighlightClipConfirmationNavigation

    @Published private(set) var workingItem: HighlightClipReviewItem
    @Published private(set) var hasChanges = false
    @Published private(set) var isSaving = false
    @Published private(set) var saveErrorMessage: String?

    let video: SelectedTrainingVideo
    let markerLabelStyle: MarkerLabelStyle
    private var openedItem: HighlightClipReviewItem
    private var entryItem: HighlightClipReviewItem
    @Published private(set) var isUsingInheritedFraming = false
    @Published private(set) var isUsingInheritedMarkerLabelPlacement = false
    private let confirmWorkingCopy: ConfirmWorkingCopy

    init(
        item: HighlightClipReviewItem,
        video: SelectedTrainingVideo,
        inheritedFraming: ClipFraming? = nil,
        markerLabelStyle: MarkerLabelStyle = .default,
        inheritedMarkerLabelPlacement: MarkerLabelPlacement? = nil,
        confirmWorkingCopy: @escaping ConfirmWorkingCopy,
    ) {
        openedItem = item
        var initialItem = item
        if item.framing == nil, let inheritedFraming {
            initialItem.framing = inheritedFraming.normalized
        }
        if item.markerLabelPlacement == nil, let inheritedMarkerLabelPlacement, inheritedMarkerLabelPlacement.isValid {
            initialItem.markerLabelPlacement = inheritedMarkerLabelPlacement
        }
        workingItem = initialItem
        entryItem = initialItem
        self.video = video
        self.markerLabelStyle = markerLabelStyle.normalized
        self.confirmWorkingCopy = confirmWorkingCopy
        isUsingInheritedFraming = item.framing == nil && inheritedFraming != nil
        isUsingInheritedMarkerLabelPlacement = item.markerLabelPlacement == nil
            && inheritedMarkerLabelPlacement?.isValid == true
    }

    var effectiveFraming: ClipFraming { (workingItem.framing ?? .original).normalized }

    var effectiveMarkerLabelPlacement: MarkerLabelPlacement {
        workingItem.markerLabelPlacement ?? MarkerLabelPlacement(style: markerLabelStyle)
    }

    func setMarkerLabelPlacement(_ placement: MarkerLabelPlacement) {
        guard !isSaving else { return }
        var editedItem = workingItem
        // Gesture input quantizes its changed coordinates. Clamp invalid fields here
        // without rounding legal saved centers when only the font size changes.
        editedItem.markerLabelPlacement = MarkerLabelPlacement(style: placement.applying(to: .default).normalized)
        applyEffectiveChange(editedItem)
    }

    func setFraming(_ framing: ClipFraming) {
        guard !isSaving else { return }
        var editedItem = workingItem
        editedItem.framing = framing.normalized
        applyEffectiveChange(editedItem)
    }

    func restoreOriginalFraming() {
        setFraming(.original)
    }

    var displayedConfirmationState: HighlightClipConfirmationState {
        openedItem.confirmationState == .confirmed && !hasChanges
            ? .confirmed
            : .defaultValue
    }

    func apply(_ edit: HighlightClipRangeEdit) throws {
        guard !isSaving else {
            return
        }
        let editedItem = try HighlightClipReviewPlanner.apply(
            edit,
            to: workingItem,
            videoDuration: video.duration,
        )
        applyEffectiveChange(editedItem)
    }

    func adjustStart(by delta: TimeInterval) throws {
        try apply(.setStart(workingItem.start + delta))
    }

    func adjustEnd(by delta: TimeInterval) throws {
        try apply(.setEnd(workingItem.range.end + delta))
    }

    func moveRange(by delta: TimeInterval) throws {
        try apply(.moveBy(delta))
    }

    func setIncluded(_ isIncluded: Bool) {
        guard !isSaving else {
            return
        }
        var editedItem = workingItem
        editedItem.isIncluded = isIncluded
        applyEffectiveChange(editedItem)
    }

    func restoreDefault() {
        guard !isSaving else {
            return
        }
        var editedItem = workingItem
        editedItem.start = workingItem.defaultStart
        editedItem.duration = workingItem.defaultDuration
        applyEffectiveChange(editedItem)
    }

    func discardChanges() {
        guard !isSaving else {
            return
        }
        workingItem = entryItem
        hasChanges = false
        saveErrorMessage = nil
    }

    func reloadSavedItem(_ item: HighlightClipReviewItem) {
        guard !isSaving, item.id == workingItem.id, item.videoID == video.id else { return }
        workingItem = item
        openedItem = item
        entryItem = item
        isUsingInheritedFraming = false
        isUsingInheritedMarkerLabelPlacement = false
        hasChanges = false
        saveErrorMessage = nil
    }

    func confirm(isIncluded: Bool) async -> HighlightClipConfirmationNavigation? {
        guard !isSaving else { return nil }
        setIncluded(isIncluded)
        return await confirm()
    }

    func confirm() async -> HighlightClipConfirmationNavigation? {
        guard !isSaving else {
            return nil
        }

        isSaving = true
        var submittedItem = workingItem
        submittedItem.framing = effectiveFraming
        submittedItem.markerLabelPlacement = effectiveMarkerLabelPlacement
        defer {
            isSaving = false
        }

        do {
            let navigation = try await confirmWorkingCopy(submittedItem)
            var confirmedItem = submittedItem
            confirmedItem.confirmationState = .confirmed
            workingItem = confirmedItem
            openedItem = confirmedItem
            entryItem = confirmedItem
            isUsingInheritedFraming = false
            isUsingInheritedMarkerLabelPlacement = false
            hasChanges = false
            saveErrorMessage = nil
            return navigation
        } catch {
            saveErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return nil
        }
    }

    private func applyEffectiveChange(_ editedItem: HighlightClipReviewItem) {
        guard editedItem != workingItem else {
            return
        }
        workingItem = editedItem
        hasChanges = workingItem.start != entryItem.start
            || workingItem.duration != entryItem.duration
            || workingItem.isIncluded != entryItem.isIncluded
            || effectiveFraming != (entryItem.framing ?? .original).normalized
            || effectiveMarkerLabelPlacement != (entryItem.markerLabelPlacement ?? MarkerLabelPlacement(style: markerLabelStyle))
    }
}

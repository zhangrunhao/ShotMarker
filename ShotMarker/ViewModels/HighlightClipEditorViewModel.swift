import Combine
import Foundation

enum HighlightClipConfirmationNavigation: Equatable {
    case open(itemID: UUID)
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
    private var openedItem: HighlightClipReviewItem
    private let confirmWorkingCopy: ConfirmWorkingCopy

    init(
        item: HighlightClipReviewItem,
        video: SelectedTrainingVideo,
        confirmWorkingCopy: @escaping ConfirmWorkingCopy,
    ) {
        openedItem = item
        workingItem = item
        self.video = video
        self.confirmWorkingCopy = confirmWorkingCopy
    }

    var displayedConfirmationState: HighlightClipConfirmationState {
        openedItem.confirmationState == .confirmed && !hasChanges
            ? .confirmed
            : .defaultValue
    }

    func apply(_ edit: HighlightClipRangeEdit) throws {
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
        var editedItem = workingItem
        editedItem.isIncluded = isIncluded
        applyEffectiveChange(editedItem)
    }

    func restoreDefault() {
        var editedItem = workingItem
        editedItem.start = workingItem.defaultStart
        editedItem.duration = workingItem.defaultDuration
        applyEffectiveChange(editedItem)
    }

    func discardChanges() {
        workingItem = openedItem
        hasChanges = false
        saveErrorMessage = nil
    }

    func confirm() async -> HighlightClipConfirmationNavigation? {
        guard !isSaving else {
            return nil
        }

        isSaving = true
        defer {
            isSaving = false
        }

        do {
            let navigation = try await confirmWorkingCopy(workingItem)
            workingItem.confirmationState = .confirmed
            openedItem = workingItem
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
        hasChanges = true
    }
}

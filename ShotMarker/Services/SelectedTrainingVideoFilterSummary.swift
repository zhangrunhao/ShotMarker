import Foundation

nonisolated struct SelectedTrainingVideoFilterSummary: Equatable {
    enum PresentationAction: Equatable {
        case none
        case clearPickerSelection
    }

    let requestedItemCount: Int
    let retainedVideoCount: Int
    let failedToLoadCount: Int
    let noMarkerCoverageCount: Int

    var filteredVideoCount: Int {
        failedToLoadCount + noMarkerCoverageCount
    }

    var shouldClearPickerSelection: Bool {
        requestedItemCount > 0 && retainedVideoCount == 0 && filteredVideoCount > 0
    }

    var presentationAction: PresentationAction {
        shouldClearPickerSelection ? .clearPickerSelection : .none
    }
}

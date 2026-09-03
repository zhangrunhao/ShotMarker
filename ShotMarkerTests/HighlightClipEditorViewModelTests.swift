@testable import ShotMarker
import XCTest

@MainActor
final class HighlightClipEditorViewModelTests: XCTestCase {
    func testOpeningDefaultAndConfirmedItemsCopiesEffectiveValues() {
        let defaultItem = makeItem(state: .defaultValue)
        let confirmedItem = makeItem(
            start: 12,
            duration: 3,
            included: false,
            state: .confirmed,
        )

        let defaultVM = makeViewModel(item: defaultItem)
        let confirmedVM = makeViewModel(item: confirmedItem)

        XCTAssertEqual(defaultVM.workingItem, defaultItem)
        XCTAssertEqual(defaultVM.displayedConfirmationState, .defaultValue)
        XCTAssertEqual(confirmedVM.workingItem, confirmedItem)
        XCTAssertEqual(confirmedVM.displayedConfirmationState, .confirmed)
        XCTAssertFalse(defaultVM.hasChanges)
        XCTAssertFalse(confirmedVM.hasChanges)
    }

    func testEveryEditChangesOnlyWorkingCopyAndConfirmedStateBecomesDefault() throws {
        let original = makeItem(state: .confirmed)
        let viewModel = makeViewModel(item: original)

        try viewModel.adjustStart(by: 0.5)
        viewModel.setIncluded(false)

        XCTAssertEqual(original.start, 10)
        XCTAssertTrue(original.isIncluded)
        XCTAssertNotEqual(viewModel.workingItem, original)
        XCTAssertTrue(viewModel.hasChanges)
        XCTAssertEqual(viewModel.displayedConfirmationState, .defaultValue)
    }

    func testRestoreDefaultChangesRangeOnly() {
        let viewModel = makeViewModel(
            item: makeItem(
                defaultStart: 8,
                defaultDuration: 5,
                start: 10,
                duration: 2,
                included: false,
                state: .confirmed,
            ),
        )

        viewModel.restoreDefault()

        XCTAssertEqual(viewModel.workingItem.range, HighlightClipRange(start: 8, duration: 5))
        XCTAssertFalse(viewModel.workingItem.isIncluded)
        XCTAssertTrue(viewModel.hasChanges)
        XCTAssertEqual(viewModel.displayedConfirmationState, .defaultValue)
    }

    func testChangingThenReturningToOpenedValuesStaysDirtyUntilConfirmOrDiscard() throws {
        let viewModel = makeViewModel(item: makeItem(state: .confirmed))

        try viewModel.moveRange(by: 1)
        try viewModel.moveRange(by: -1)

        XCTAssertEqual(viewModel.workingItem.range, HighlightClipRange(start: 10, duration: 2))
        XCTAssertTrue(viewModel.hasChanges)
        XCTAssertEqual(viewModel.displayedConfirmationState, .defaultValue)
    }

    func testDiscardRestoresOpenedValueAndClearsError() async throws {
        let original = makeItem(state: .confirmed)
        let viewModel = makeViewModel(
            item: original,
            confirm: { _ in throw TestError.saveFailed },
        )
        try viewModel.moveRange(by: 1)
        _ = await viewModel.confirm()

        viewModel.discardChanges()

        XCTAssertEqual(viewModel.workingItem, original)
        XCTAssertEqual(viewModel.displayedConfirmationState, .confirmed)
        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertNil(viewModel.saveErrorMessage)
    }

    func testConfirmPassesWorkingCopyAndMarksItConfirmedOnSuccess() async throws {
        let recorder = ConfirmationRecorder(result: .success(.returnToReview))
        let viewModel = makeViewModel(item: makeItem(), confirm: recorder.confirm)
        try viewModel.adjustEnd(by: 0.5)

        let navigation = await viewModel.confirm()
        let submitted = await recorder.items()

        XCTAssertEqual(navigation, .returnToReview)
        XCTAssertEqual(submitted.count, 1)
        XCTAssertEqual(submitted[0].range, viewModel.workingItem.range)
        XCTAssertEqual(submitted[0].isIncluded, viewModel.workingItem.isIncluded)
        XCTAssertEqual(submitted[0].confirmationState, .defaultValue)
        XCTAssertEqual(viewModel.displayedConfirmationState, .confirmed)
        XCTAssertFalse(viewModel.hasChanges)
        XCTAssertNil(viewModel.saveErrorMessage)
    }

    func testFailedConfirmKeepsWorkingCopyDefaultStateAndAllowsRetry() async throws {
        let recorder = ConfirmationRecorder(result: .failure(TestError.saveFailed))
        let viewModel = makeViewModel(
            item: makeItem(state: .confirmed),
            confirm: recorder.confirm,
        )
        try viewModel.moveRange(by: 1)
        let edited = viewModel.workingItem

        let navigation = await viewModel.confirm()

        XCTAssertNil(navigation)
        XCTAssertEqual(viewModel.workingItem, edited)
        XCTAssertEqual(viewModel.displayedConfirmationState, .defaultValue)
        XCTAssertNotNil(viewModel.saveErrorMessage)
        XCTAssertFalse(viewModel.isSaving)
    }

    func testConcurrentButtonActionsInvokeConfirmationOnce() async {
        let gate = ConfirmationGate()
        let viewModel = makeViewModel(item: makeItem(), confirm: gate.confirm)

        async let first = viewModel.confirm()
        await gate.waitUntilEntered()
        async let second = viewModel.confirm()
        await Task.yield()
        await gate.release(with: .open(itemID: makeItem().id))
        _ = await (first, second)

        let callCount = await gate.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testEditsAndDiscardAreIgnoredWhileConfirmationIsSaving() async throws {
        let gate = ConfirmationGate()
        let viewModel = makeViewModel(
            item: makeItem(state: .confirmed),
            confirm: gate.confirm,
        )
        try viewModel.moveRange(by: 1)
        let submittedItem = viewModel.workingItem
        let confirmation = Task { await viewModel.confirm() }
        await gate.waitUntilEntered()

        try viewModel.moveRange(by: -1)
        viewModel.setIncluded(false)
        viewModel.restoreDefault()
        viewModel.discardChanges()

        XCTAssertEqual(viewModel.workingItem, submittedItem)
        XCTAssertTrue(viewModel.hasChanges)

        await gate.release(with: .returnToReview)
        _ = await confirmation.value

        var confirmedSubmittedItem = submittedItem
        confirmedSubmittedItem.confirmationState = .confirmed
        XCTAssertEqual(viewModel.workingItem, confirmedSubmittedItem)
        XCTAssertEqual(viewModel.displayedConfirmationState, .confirmed)
        XCTAssertFalse(viewModel.hasChanges)
    }
}

@MainActor
private func makeViewModel(
    item: HighlightClipReviewItem,
    confirm: @escaping HighlightClipEditorViewModel.ConfirmWorkingCopy = {
        _ in .returnToReview
    },
) -> HighlightClipEditorViewModel {
    HighlightClipEditorViewModel(
        item: item,
        video: SelectedTrainingVideo(
            id: item.videoID,
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
            reviewSourceIdentity: .photoLibraryAsset("editor-asset"),
        ),
        confirmWorkingCopy: confirm,
    )
}

private func makeItem(
    defaultStart: TimeInterval = 10,
    defaultDuration: TimeInterval = 2,
    start: TimeInterval = 10,
    duration: TimeInterval = 2,
    included: Bool = true,
    state: HighlightClipConfirmationState = .defaultValue,
) -> HighlightClipReviewItem {
    let markerID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000501",
    )!
    return HighlightClipReviewItem(
        id: markerID,
        videoID: "runtime-video",
        markerReferences: [
            HighlightClipMarkerReference(
                id: markerID,
                markedAt: Date(timeIntervalSince1970: 110),
                timeInVideo: 10,
                originalMatchedNumber: 1,
            ),
        ],
        defaultStart: defaultStart,
        defaultDuration: defaultDuration,
        start: start,
        duration: duration,
        isIncluded: included,
        confirmationState: state,
    )
}

private actor ConfirmationRecorder {
    private let result: Result<HighlightClipConfirmationNavigation, TestError>
    private var received: [HighlightClipReviewItem] = []

    init(result: Result<HighlightClipConfirmationNavigation, TestError>) {
        self.result = result
    }

    func confirm(
        _ item: HighlightClipReviewItem,
    ) async throws -> HighlightClipConfirmationNavigation {
        received.append(item)
        return try result.get()
    }

    func items() -> [HighlightClipReviewItem] {
        received
    }
}

private actor ConfirmationGate {
    private var entered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation:
        CheckedContinuation<HighlightClipConfirmationNavigation, Never>?
    private var invocations = 0

    func confirm(
        _: HighlightClipReviewItem,
    ) async throws -> HighlightClipConfirmationNavigation {
        invocations += 1
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func release(with result: HighlightClipConfirmationNavigation) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }

    func callCount() -> Int {
        invocations
    }
}

private enum TestError: LocalizedError, Equatable {
    case saveFailed

    var errorDescription: String? { "saveFailed" }
}

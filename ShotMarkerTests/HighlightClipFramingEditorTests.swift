@testable import ShotMarker
import AVFoundation
import XCTest

@MainActor
final class HighlightClipFramingEditorTests: XCTestCase {
    private let zoom = ClipFraming(scale: 2.2, centerX: 0.6, centerY: 0.4)

    func testSameSourceKeepAndExcludePassSavedFramingOnlyAfterSuccess() async throws {
        for included in [true, false] {
            var writes: [HighlightClipReviewItem] = []
            let vm = makeReview { writes.append($0) }
            let first = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
            first.setFraming(zoom)
            let navigation = await first.confirm(isIncluded: included)
            XCTAssertEqual(navigation, .continueReview(itemID: vm.items[1].id, sourceVideoID: "a", framing: zoom))
            XCTAssertEqual(writes.first?.framing, zoom)
            XCTAssertEqual(writes.first?.isIncluded, included)
            XCTAssertEqual(vm.items[0].framing, zoom)
            let next = try XCTUnwrap(navigation.flatMap { vm.makeEditorViewModel(navigation: $0) })
            XCTAssertEqual(next.effectiveFraming, zoom)
            XCTAssertFalse(next.hasChanges)
            XCTAssertNil(vm.items[1].framing)
        }
    }

    func testCrossSourceAutomaticNavigationUsesTargetsOwnSavedValue() async throws {
        let target = ClipFraming(scale: 3, centerX: 0.4, centerY: 0.6)
        let vm = makeReview(secondVideoID: "b", secondFraming: target)
        let first = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
        first.setFraming(zoom)
        let navigation = await first.confirm()
        XCTAssertEqual(navigation, .open(itemID: vm.items[1].id))
        let next = try XCTUnwrap(navigation.flatMap { vm.makeEditorViewModel(navigation: $0) })
        XCTAssertEqual(next.effectiveFraming, target)
    }

    func testInheritedFramingOverridesSavedTargetTemporarilyAndManualReopenRestoresSavedValue() throws {
        let saved = ClipFraming(scale: 3, centerX: 0.4, centerY: 0.6)
        let vm = makeReview(secondFraming: saved)
        let targetID = vm.items[1].id
        let inherited = try XCTUnwrap(vm.makeEditorViewModel(itemID: targetID, inheritedFraming: zoom))
        XCTAssertEqual(inherited.effectiveFraming, zoom)
        XCTAssertTrue(inherited.isUsingInheritedFraming)
        XCTAssertFalse(inherited.hasChanges)
        XCTAssertEqual(vm.items[1].framing, saved)
        let manual = try XCTUnwrap(vm.makeEditorViewModel(itemID: targetID))
        XCTAssertEqual(manual.effectiveFraming, saved)
        XCTAssertFalse(manual.isUsingInheritedFraming)
    }

    func testManualReopenOfUnsavedTargetUsesOriginalAndDoesNotReceiveLastFraming() async throws {
        let vm = makeReview()
        let first = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
        first.setFraming(zoom)
        _ = await first.confirm()
        XCTAssertEqual(vm.makeEditorViewModel(itemID: vm.items[1].id)?.effectiveFraming, .original)
    }

    func testReturningAllEditsToInheritedBaselineClearsDirtyAndRangeResetPreservesFraming() throws {
        let vm = makeReview()
        let editor = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id, inheritedFraming: zoom))
        editor.restoreOriginalFraming()
        XCTAssertTrue(editor.hasChanges)
        XCTAssertEqual(editor.workingItem.range, .init(start: 5, duration: 2))
        editor.setFraming(zoom)
        XCTAssertFalse(editor.hasChanges)
        try editor.moveRange(by: 1)
        editor.restoreDefault()
        XCTAssertEqual(editor.effectiveFraming, zoom)
        XCTAssertFalse(editor.hasChanges)
        editor.setIncluded(false)
        editor.setIncluded(true)
        XCTAssertFalse(editor.hasChanges)
    }

    func testFailedSaveRetainsFramingAndTargetWhilePublishingNoNavigation() async throws {
        let vm = makeReview { _ in throw FramingFailure.write }
        let editor = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
        editor.setFraming(zoom)
        let navigation = await editor.confirm(isIncluded: false)
        XCTAssertNil(navigation)
        XCTAssertEqual(vm.editingItemID, vm.items[0].id)
        XCTAssertNil(vm.items[0].framing)
        XCTAssertNil(vm.items[1].framing)
        XCTAssertEqual(editor.effectiveFraming, zoom)
        XCTAssertTrue(editor.hasChanges)
        XCTAssertNotNil(editor.saveErrorMessage)
    }

    func testUndoRestoresMissingExplicitOriginalAndZoomWithoutInheritance() async throws {
        for prior in [nil, ClipFraming.original, zoom] {
            var writes: [HighlightClipReviewItem] = []
            let vm = makeReview(firstFraming: prior) { writes.append($0) }
            let editor = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
            editor.setFraming(ClipFraming(scale: 4, centerX: 0.5, centerY: 0.5))
            _ = await editor.confirm(isIncluded: false)
            let restoredID = await vm.undoLastDecision()
            XCTAssertEqual(restoredID, vm.items[0].id)
            XCTAssertEqual(vm.items[0].framing, prior)
            XCTAssertEqual(writes.last?.framing, prior)
            let reopened = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
            XCTAssertEqual(reopened.effectiveFraming, prior ?? .original)
            XCTAssertFalse(reopened.isUsingInheritedFraming)
        }
    }

    func testMismatchedAutomaticNavigationCannotApplyFramingToAnotherSource() {
        let vm = makeReview(secondVideoID: "b")
        XCTAssertNil(vm.makeEditorViewModel(navigation: .continueReview(itemID: vm.items[1].id, sourceVideoID: "a", framing: zoom)))
        XCTAssertNil(vm.makeEditorViewModel(navigation: .continueReview(itemID: UUID(), sourceVideoID: "a", framing: zoom)))
    }

    func testReloadAfterUndoClearsInheritedBaselineAndLateLoadCannotChangeFraming() throws {
        let vm = makeReview()
        let original = vm.items[0]
        let editor = try XCTUnwrap(vm.makeEditorViewModel(itemID: original.id, inheritedFraming: zoom))
        editor.reloadSavedItem(original)
        XCTAssertEqual(editor.effectiveFraming, .original)
        XCTAssertFalse(editor.isUsingInheritedFraming)
        XCTAssertFalse(editor.hasChanges)
        editor.setFraming(zoom)
        editor.discardChanges()
        XCTAssertEqual(editor.effectiveFraming, .original)
    }

    private func makeReview(
        secondVideoID: String = "a",
        firstFraming: ClipFraming? = nil,
        secondFraming: ClipFraming? = nil,
        persist: @escaping (HighlightClipReviewItem) async throws -> Void = { _ in }
    ) -> HighlightClipReviewViewModel {
        let videos = ["a", "b"].map { SelectedTrainingVideo(id: $0, recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60) }
        let items = ["a", secondVideoID].enumerated().map { index, source in
            let marker = HighlightClipMarkerReference(id: UUID(), markedAt: Date(timeIntervalSince1970: 106 + Double(index * 10)), timeInVideo: 6 + Double(index * 10), originalMatchedNumber: index + 1)
            return HighlightClipReviewItem(id: UUID(), videoID: source, markerReferences: [marker], defaultStart: 5 + Double(index * 10), defaultDuration: 2, start: 5 + Double(index * 10), duration: 2, isIncluded: true, framing: index == 0 ? firstFraming : secondFraming)
        }
        return HighlightClipReviewViewModel(draft: .init(selectedVideoCount: 2, totalMarkerCount: 2, items: items), videos: videos, clipSettings: .default, persistReviewItem: persist,
            mediaProvider: HighlightClipReviewMediaProvider(cacheLimit: 0, loadAsset: { _ in AVMutableComposition() }, generateFrame: { _, _ in Data() }), submitSegments: { _ in })
    }
}

private enum FramingFailure: Error { case write }

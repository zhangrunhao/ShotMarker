@testable import ShotMarker
import AVFoundation
import XCTest

@MainActor
final class HighlightClipLabelEditorTests: XCTestCase {
    private let moved = MarkerLabelPlacement(fontSizeRatio: 0.16, normalizedCenterX: 0.8, normalizedCenterY: 0.7)
    private let defaults = MarkerLabelPlacement(fontSizeRatio: 0.1, normalizedCenterX: 0.15, normalizedCenterY: 0.1)

    func testFontSizeRoundTripPreservesSavedPreciseCentersAndClearsDirty() async throws {
        let precise = MarkerLabelPlacement(fontSizeRatio: 0.1,
            normalizedCenterX: 0.1234567, normalizedCenterY: 0.7654321)
        var writes: [HighlightClipReviewItem] = []
        let vm = makeReview(saved: precise) { writes.append($0) }
        let editor = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[1].id))

        editor.setMarkerLabelPlacement(MarkerLabelPlacement(fontSizeRatio: 0.11,
            normalizedCenterX: 0.1234567, normalizedCenterY: 0.7654321))

        XCTAssertTrue(editor.hasChanges)
        XCTAssertEqual(editor.effectiveMarkerLabelPlacement.normalizedCenterX, 0.1234567)
        XCTAssertEqual(editor.effectiveMarkerLabelPlacement.normalizedCenterY, 0.7654321)
        editor.setMarkerLabelPlacement(precise)
        XCTAssertEqual(editor.effectiveMarkerLabelPlacement, precise)
        XCTAssertFalse(editor.hasChanges)
        _ = await editor.confirm()
        XCTAssertEqual(writes.last?.markerLabelPlacement, precise)
    }

    func testInvalidSetterInputClampsOnlyInvalidFieldsWithoutRoundingLegalCenters() throws {
        let vm = makeReview()
        let editor = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
        editor.setMarkerLabelPlacement(MarkerLabelPlacement(fontSizeRatio: 0.2,
            normalizedCenterX: 0.1234567, normalizedCenterY: 0.7654321))
        XCTAssertEqual(editor.effectiveMarkerLabelPlacement, MarkerLabelPlacement(fontSizeRatio: 0.16,
            normalizedCenterX: 0.1234567, normalizedCenterY: 0.7654321))
        editor.setMarkerLabelPlacement(MarkerLabelPlacement(fontSizeRatio: .nan,
            normalizedCenterX: -1, normalizedCenterY: .infinity))
        XCTAssertEqual(editor.effectiveMarkerLabelPlacement, MarkerLabelPlacement(fontSizeRatio: 0.1,
            normalizedCenterX: 0, normalizedCenterY: 0.1))
    }

    func testKeepAndExcludeSaveSnapshotAndSameSourceInheritanceIsClean() async throws {
        for included in [true, false] {
            var writes: [HighlightClipReviewItem] = []
            let vm = makeReview { writes.append($0) }
            let first = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
            first.setMarkerLabelPlacement(moved)
            let result = await first.confirm(isIncluded: included)
            let navigation = try XCTUnwrap(result)
            XCTAssertEqual(writes.first?.markerLabelPlacement, moved)
            XCTAssertEqual(writes.first?.isIncluded, included)
            XCTAssertEqual(vm.items[0].markerLabelPlacement, moved)
            let next = try XCTUnwrap(vm.makeEditorViewModel(navigation: navigation))
            XCTAssertEqual(next.effectiveMarkerLabelPlacement, moved)
            XCTAssertFalse(next.hasChanges)
            XCTAssertNil(vm.items[1].markerLabelPlacement)
            next.setMarkerLabelPlacement(defaults)
            XCTAssertTrue(next.hasChanges)
            next.setMarkerLabelPlacement(moved)
            XCTAssertFalse(next.hasChanges)
            _ = await next.confirm()
            XCTAssertEqual(vm.items[1].markerLabelPlacement, moved)
        }
    }

    func testSavedTargetOverridesInheritanceAndManualReopenIsIndependent() async throws {
        for saved in [nil, defaults, moved] {
            let vm = makeReview(saved: saved)
            let first = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
            let prior = MarkerLabelPlacement(fontSizeRatio: 0.04, normalizedCenterX: 0.4, normalizedCenterY: 0.4)
            first.setMarkerLabelPlacement(prior)
            let result = await first.confirm()
            let navigation = try XCTUnwrap(result)
            let next = try XCTUnwrap(vm.makeEditorViewModel(navigation: navigation))
            XCTAssertEqual(next.effectiveMarkerLabelPlacement, saved ?? prior)
            let manual = try XCTUnwrap(vm.makeEditorViewModel(navigation: .open(itemID: vm.items[1].id)))
            XCTAssertEqual(manual.effectiveMarkerLabelPlacement, saved ?? defaults)
            manual.setMarkerLabelPlacement(prior)
            let reopened = try XCTUnwrap(vm.makeEditorViewModel(navigation: .open(itemID: vm.items[1].id)))
            XCTAssertEqual(reopened.effectiveMarkerLabelPlacement, saved ?? defaults)
            XCTAssertFalse(reopened.hasChanges)
        }
    }

    func testCrossSourceAndStaleNavigationDoNotInherit() async throws {
        let vm = makeReview(secondSource: "b")
        let first = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
        first.setMarkerLabelPlacement(moved)
        let result = await first.confirm()
        let navigation = try XCTUnwrap(result)
        XCTAssertEqual(navigation, .open(itemID: vm.items[1].id))
        XCTAssertEqual(vm.makeEditorViewModel(navigation: navigation)?.effectiveMarkerLabelPlacement, defaults)
        XCTAssertNil(vm.makeEditorViewModel(navigation: .continueReview(itemID: vm.items[1].id,
            sourceVideoID: "a", framing: .original, markerLabelPlacement: moved)))
    }

    func testFailedSavePreservesWorkingPlacementAndNoNavigation() async throws {
        let vm = makeReview { _ in throw HighlightTaskError.revisionConflict }
        let editor = try XCTUnwrap(vm.makeEditorViewModel(itemID: vm.items[0].id))
        editor.setMarkerLabelPlacement(moved)
        let navigation = await editor.confirm(isIncluded: false)
        XCTAssertNil(navigation)
        XCTAssertTrue(editor.hasChanges)
        XCTAssertEqual(editor.effectiveMarkerLabelPlacement, moved)
        XCTAssertEqual(vm.editingItemID, vm.items[0].id)
        XCTAssertNil(vm.items[0].markerLabelPlacement)
        editor.discardChanges()
        XCTAssertEqual(editor.effectiveMarkerLabelPlacement, defaults)
        XCTAssertFalse(editor.hasChanges)
    }

    private func makeReview(secondSource: String = "a", saved: MarkerLabelPlacement? = nil,
        persist: @escaping (HighlightClipReviewItem) async throws -> Void = { _ in }) -> HighlightClipReviewViewModel {
        let videos = ["a", "b"].map { SelectedTrainingVideo(id: $0, recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60) }
        let items = ["a", secondSource].enumerated().map { index, source in
            let marker = HighlightClipMarkerReference(id: UUID(), markedAt: Date(timeIntervalSince1970: 106 + Double(index * 10)), timeInVideo: 6 + Double(index * 10), originalMatchedNumber: index + 1)
            return HighlightClipReviewItem(id: UUID(), videoID: source, markerReferences: [marker], defaultStart: 5 + Double(index * 10), defaultDuration: 2, start: 5 + Double(index * 10), duration: 2, isIncluded: true, markerLabelPlacement: index == 0 ? nil : saved)
        }
        return HighlightClipReviewViewModel(draft: .init(selectedVideoCount: 2, totalMarkerCount: 2, items: items), videos: videos, clipSettings: .default, persistReviewItem: persist,
            mediaProvider: HighlightClipReviewMediaProvider(cacheLimit: 0, loadAsset: { _ in AVMutableComposition() }, generateFrame: { _, _ in Data() }), submitSegments: { _ in })
    }
}

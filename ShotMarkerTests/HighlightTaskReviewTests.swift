@testable import ShotMarker
import AVFoundation
import XCTest

final class HighlightTaskReviewTests: XCTestCase {
    func testRetainedThumbnailDataIsBoundedAndReleaseDropsCachedAsset() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let start = Date(timeIntervalSince1970: 100)
        let task = try await fixture.manager.createTask(session:
            TrainingSession(startedAt: start, endedAt: start.addingTimeInterval(1_500),
                events: (0..<70).map { ShotMarkerEvent(markedAt: start.addingTimeInterval(Double($0 * 20 + 10))) }),
            selectedVideos: [SelectedTrainingVideo(id: "fixture", recordedStartAt: start, duration: 1_500)], settings: .default)
        weak var cachedAsset: AVAsset?
        let media = HighlightClipReviewMediaProvider(loadAsset: { _ in
            let asset = AVMutableComposition()
            cachedAsset = asset
            return asset
        }, generateFrame: { _, _ in Data([1]) })
        let session = try HighlightReviewSession(task: task, manager: fixture.manager, mediaProvider: media)
        for item in task.reviewItems {
            await session.viewModel.loadThumbnail(itemID: item.id, targetSize: .init(width: 10, height: 10))
        }
        XCTAssertEqual(task.reviewItems.count, 70)
        XCTAssertEqual(session.viewModel.thumbnailStates.values.filter { if case .loaded = $0 { true } else { false } }.count, 64)
        XCTAssertNotNil(cachedAsset)
        session.release()
        XCTAssertNil(cachedAsset)
        XCTAssertTrue(session.viewModel.thumbnailStates.isEmpty)
    }

    func testConfirmationWritesTaskRevisionBeforePublishingAndNextCardNavigation() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let session = try HighlightReviewSession(task: task, manager: fixture.manager, mediaProvider: provider())
        let first = task.reviewItems[0]
        let editor = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: first.id))
        editor.setIncluded(false)
        XCTAssertTrue(session.viewModel.items[0].isIncluded)
        let navigation = await editor.confirm()
        XCTAssertEqual(navigation, .open(itemID: task.reviewItems[1].id))
        XCTAssertEqual(fixture.manager.task(task.id)?.configurationRevision, 2)
        XCTAssertFalse(session.viewModel.items[0].isIncluded)
        let loaded = try await fixture.storeFixture.store.load()
        XCTAssertEqual(loaded[0].reviewItems[0].confirmationState, .confirmed)
        XCTAssertFalse(loaded[0].reviewItems[0].isIncluded)
    }

    func testUndoRestoresDefaultRangeInclusionAndConfirmationOnDisk() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let session = try HighlightReviewSession(task: task, manager: fixture.manager, mediaProvider: provider())
        let original = session.viewModel.items[0]
        let editor = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: original.id))
        try editor.moveRange(by: 1)
        editor.setIncluded(false)
        _ = await editor.confirm()
        XCTAssertEqual(session.viewModel.lastDecision?.itemID, original.id)
        XCTAssertEqual(session.viewModel.lastDecision?.isIncluded, false)

        let restoredID = await session.viewModel.undoLastDecision()

        XCTAssertEqual(restoredID, original.id)
        XCTAssertEqual(session.viewModel.items[0], original)
        XCTAssertEqual(session.viewModel.editingItemID, original.id)
        XCTAssertNil(session.viewModel.lastDecision)
        XCTAssertNil(session.viewModel.undoErrorMessage)
        let reloaded = try await HighlightTaskStore(fileURL: fixture.storeFixture.fileURL).load()
        XCTAssertEqual(reloaded[0].configurationRevision, 3)
        XCTAssertEqual(reloaded[0].reviewItems[0], task.reviewItems[0])
        let reopened = try HighlightReviewSession(task: reloaded[0], manager: fixture.manager, mediaProvider: provider())
        XCTAssertEqual(reopened.viewModel.items[0], original)
        XCTAssertNil(reopened.viewModel.lastDecision)
    }

    func testUndoRestoresPriorConfirmedDecisionAndAdjustedRange() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let session = try HighlightReviewSession(task: task, manager: fixture.manager, mediaProvider: provider())
        let itemID = task.reviewItems[0].id
        let first = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: itemID))
        try first.moveRange(by: 1)
        first.setIncluded(false)
        _ = await first.confirm()
        let priorDecision = session.viewModel.items[0]
        let second = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: itemID))
        try second.moveRange(by: 2)
        second.setIncluded(true)
        _ = await second.confirm()

        let restoredID = await session.viewModel.undoLastDecision()

        XCTAssertEqual(restoredID, itemID)
        XCTAssertEqual(session.viewModel.items[0], priorDecision)
        XCTAssertEqual(session.viewModel.items[0].confirmationState, .confirmed)
        XCTAssertFalse(session.viewModel.items[0].isIncluded)
        let reloaded = try await fixture.storeFixture.store.load()
        XCTAssertEqual(reloaded[0].reviewItems[0].start, priorDecision.start)
        XCTAssertEqual(reloaded[0].reviewItems[0].duration, priorDecision.duration)
        XCTAssertEqual(reloaded[0].reviewItems[0].confirmationState, .confirmed)
        XCTAssertFalse(reloaded[0].reviewItems[0].isIncluded)
    }

    func testUndoOnlyRevertsLatestDecisionAndDoesNotCreateAnotherUndo() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let session = try HighlightReviewSession(task: task, manager: fixture.manager, mediaProvider: provider())
        for item in session.viewModel.items {
            let editor = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: item.id))
            editor.setIncluded(false)
            _ = await editor.confirm()
        }
        XCTAssertNil(session.viewModel.editingItemID)

        let restoredID = await session.viewModel.undoLastDecision()
        let secondUndo = await session.viewModel.undoLastDecision()

        XCTAssertEqual(restoredID, task.reviewItems[1].id)
        XCTAssertNil(secondUndo)
        XCTAssertEqual(session.viewModel.items[0].confirmationState, .confirmed)
        XCTAssertFalse(session.viewModel.items[0].isIncluded)
        XCTAssertEqual(session.viewModel.items[1].confirmationState, .defaultValue)
        XCTAssertTrue(session.viewModel.items[1].isIncluded)
        XCTAssertNil(session.viewModel.lastDecision)
    }

    func testFailedUndoPreservesDecisionEditorAndDiskThenAllowsRetry() async throws {
        let storage = try TaskStoreFixture()
        defer { storage.cleanup() }
        let writes = ReviewWriteControl()
        let store = HighlightTaskStore(fileURL: storage.fileURL, atomicWrite: writes.write)
        let manager = HighlightTaskManager(store: store, fileStore: HighlightTaskFileStore(baseDirectory: storage.directory),
            runner: ControlledHighlightRenderRunner(), validateSource: { _ in })
        let task = try await manager.createTask(session: HighlightTaskTestFixture.session,
            selectedVideos: TaskManagerFixture.videos, settings: .default)
        let session = try HighlightReviewSession(task: task, manager: manager, mediaProvider: provider())
        let first = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: task.reviewItems[0].id))
        first.setIncluded(false)
        _ = await first.confirm()
        let savedItems = session.viewModel.items
        let savedBytes = try Data(contentsOf: storage.fileURL)
        writes.setFailing(true)

        let failedID = await session.viewModel.undoLastDecision()

        XCTAssertNil(failedID)
        XCTAssertEqual(session.viewModel.items, savedItems)
        XCTAssertEqual(session.viewModel.editingItemID, task.reviewItems[1].id)
        XCTAssertEqual(session.viewModel.lastDecision?.itemID, task.reviewItems[0].id)
        XCTAssertNotNil(session.viewModel.undoErrorMessage)
        XCTAssertFalse(session.viewModel.isUndoingDecision)
        XCTAssertEqual(try Data(contentsOf: storage.fileURL), savedBytes)
        writes.setFailing(false)

        let retriedID = await session.viewModel.undoLastDecision()

        XCTAssertEqual(retriedID, task.reviewItems[0].id)
        XCTAssertNil(session.viewModel.lastDecision)
        XCTAssertNil(session.viewModel.undoErrorMessage)
        let reloaded = try await store.load()
        XCTAssertEqual(reloaded[0].reviewItems[0], task.reviewItems[0])
    }

    func testFailedNewConfirmationKeepsPreviousUndoDecision() async throws {
        let storage = try TaskStoreFixture()
        defer { storage.cleanup() }
        let writes = ReviewWriteControl()
        let store = HighlightTaskStore(fileURL: storage.fileURL, atomicWrite: writes.write)
        let manager = HighlightTaskManager(store: store, fileStore: HighlightTaskFileStore(baseDirectory: storage.directory),
            runner: ControlledHighlightRenderRunner(), validateSource: { _ in })
        let task = try await manager.createTask(session: HighlightTaskTestFixture.session,
            selectedVideos: TaskManagerFixture.videos, settings: .default)
        let session = try HighlightReviewSession(task: task, manager: manager, mediaProvider: provider())
        let first = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: task.reviewItems[0].id))
        first.setIncluded(false)
        _ = await first.confirm()
        writes.setFailing(true)
        let second = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: task.reviewItems[1].id))
        second.setIncluded(false)

        let failedNavigation = await second.confirm()

        XCTAssertNil(failedNavigation)
        XCTAssertEqual(session.viewModel.lastDecision?.itemID, task.reviewItems[0].id)
        XCTAssertEqual(session.viewModel.editingItemID, task.reviewItems[1].id)
        XCTAssertTrue(second.hasChanges)
        XCTAssertTrue(session.viewModel.items[1].isIncluded)
    }

    func testStaleReviewRetainsWorkingCopyWithoutPublishing() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let session = try HighlightReviewSession(task: task, manager: fixture.manager, mediaProvider: provider())
        var settings = task.clipSettings
        settings.markerLabelStyle.textOpacity = 0.4
        _ = try await fixture.manager.updateConfiguration(taskID: task.id, expectedRevision: 1,
            selectedVideos: TaskManagerFixture.videos, settings: settings)
        let editor = try XCTUnwrap(session.viewModel.makeEditorViewModel(itemID: task.reviewItems[0].id))
        editor.setIncluded(false)
        let navigation = await editor.confirm()
        XCTAssertNil(navigation)
        XCTAssertTrue(editor.hasChanges)
        XCTAssertNotNil(editor.saveErrorMessage)
        XCTAssertTrue(session.viewModel.items[0].isIncluded)
        XCTAssertEqual(fixture.manager.task(task.id)?.configurationRevision, 2)
    }

    func testReleaseDropsRuntimeDataAndPreservesTaskConfiguration() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let session = try HighlightReviewSession(task: task, manager: fixture.manager, mediaProvider: provider())
        await session.viewModel.loadThumbnail(itemID: task.reviewItems[0].id, targetSize: .init(width: 10, height: 10))
        XCTAssertEqual(session.viewModel.thumbnailStates[task.reviewItems[0].id], .loaded(Data([1])))
        session.release()
        XCTAssertTrue(session.viewModel.thumbnailStates.isEmpty)
        XCTAssertTrue(session.viewModel.filmstripFramesByItemID.isEmpty)
        XCTAssertNil(session.viewModel.editingItemID)
        XCTAssertEqual(fixture.manager.task(task.id)?.reviewItems, task.reviewItems)
        XCTAssertEqual(session.viewModel.items.count, 2)
    }

    private func provider() -> HighlightClipReviewMediaProvider {
        HighlightClipReviewMediaProvider(loadAsset: { _ in AVMutableComposition() }, generateFrame: { _, _ in Data([1]) })
    }
}

private nonisolated final class ReviewWriteControl: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = false

    func setFailing(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        shouldFail = value
    }

    func write(_ data: Data, to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }
}

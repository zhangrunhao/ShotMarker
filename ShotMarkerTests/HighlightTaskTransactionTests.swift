@testable import ShotMarker
import XCTest

final class HighlightTaskTransactionTests: XCTestCase {
    func testCreationWriteFailureRemovesOnlyNewTaskFilesAndNeverPublishesTask() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let source = fixture.directory.appendingPathComponent("source.mov")
        try Data("source".utf8).write(to: source)
        let files = HighlightTaskFileStore(baseDirectory: fixture.directory)
        let store = HighlightTaskStore(fileURL: fixture.fileURL, atomicWrite: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let manager = HighlightTaskManager(store: store, fileStore: files,
            runner: ControlledHighlightRenderRunner(), validateSource: { _ in })
        do {
            _ = try await manager.createTask(session: HighlightTaskTestFixture.session,
                selectedVideos: [selection(source)], settings: .default)
            XCTFail("Expected transaction failure")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .persistence) }
        XCTAssertTrue(manager.tasks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.appendingPathComponent("HighlightTasks").path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testConfigurationWriteFailureDiscardsNewInputsAndPreservesOldInputsAndRevision() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let a = fixture.directory.appendingPathComponent("a.mov")
        let b = fixture.directory.appendingPathComponent("b.mov")
        try Data("first".utf8).write(to: a)
        try Data("second".utf8).write(to: b)
        let files = HighlightTaskFileStore(baseDirectory: fixture.directory)
        let store = HighlightTaskStore(fileURL: fixture.fileURL, atomicWrite: { data, url in
            let document = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: data)
            if document.tasks.contains(where: { $0.configurationRevision > 1 }) { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let manager = HighlightTaskManager(store: store, fileStore: files,
            runner: ControlledHighlightRenderRunner(), validateSource: { _ in })
        let task = try await manager.createTask(session: HighlightTaskTestFixture.session,
            selectedVideos: [selection(a)], settings: .default)
        let before = try Data(contentsOf: fixture.fileURL)
        do {
            _ = try await manager.updateConfiguration(taskID: task.id, expectedRevision: 1,
                selectedVideos: [selection(b)], settings: .default)
            XCTFail("Expected transaction failure")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .persistence) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
        XCTAssertEqual(manager.task(task.id), task)
        let names = try FileManager.default.contentsOfDirectory(atPath:
            fixture.directory.appendingPathComponent("HighlightTasks/\(task.id)/Inputs").path)
        XCTAssertEqual(names, ["\(task.videos[0].id).mov"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    func testOutputCommitFailurePreservesOldMovieAndDoesNotEmitSuccess() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await completedTask(fixture)
        let old = try XCTUnwrap(task.currentOutput)
        let oldURL = try fixture.manager.playbackURL(taskID: task.id)
        let store = HighlightTaskStore(fileURL: fixture.storeFixture.fileURL, atomicWrite: { data, url in
            let document = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: data)
            if document.tasks.first?.currentOutput?.id != old.id { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let analytics = SpyAnalyticsTracker()
        let runner = ControlledHighlightRenderRunner()
        let manager = HighlightTaskManager(store: store, fileStore: fixture.files,
            runner: runner, validateSource: { _ in }, analytics: analytics)
        await manager.load()
        try await manager.restart(taskID: task.id)
        await waitFor { runner.executions.count == 1 }
        runner.finishNextSuccessfully()
        await manager.waitUntilIdle()
        XCTAssertEqual(analytics.records.last?.stage, .commit)
        XCTAssertEqual(analytics.records.last?.reason, .outputCommitFailed)
        XCTAssertEqual(manager.task(task.id)?.state, .failed)
        XCTAssertEqual(manager.task(task.id)?.lastGenerationResult?.errorCode, .outputCommitFailed)
        XCTAssertEqual(manager.task(task.id)?.currentOutput, old)
        XCTAssertEqual(try Data(contentsOf: oldURL), Data("rendered".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: oldURL.deletingLastPathComponent().deletingLastPathComponent().path), [old.id.uuidString])
        XCTAssertEqual(analytics.events.map(\.rawValue), ["highlight_generate_started", "highlight_generate_failed"])
    }

    func testOutputMoveFailureRetainsPreviousMovieAndCleansExecution() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await completedTask(fixture)
        let oldURL = try fixture.manager.playbackURL(taskID: task.id)
        try await fixture.manager.restart(taskID: task.id)
        await waitFor { fixture.runner.executions.count == 2 }
        fixture.runner.finishWithMissingOutput()
        await fixture.manager.waitUntilIdle()
        XCTAssertEqual(fixture.manager.task(task.id)?.currentOutput, task.currentOutput)
        XCTAssertEqual(fixture.manager.task(task.id)?.lastGenerationResult?.errorCode, .outputCommitFailed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(fixture.analytics.events.map(\.rawValue), ["highlight_generate_started", "highlight_generate_succeeded", "highlight_generate_started", "highlight_generate_failed"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.files.temporaryDirectory.path), [])
    }

    func testPhotoSaveFailureAndSuccessKeepRevisionAndTrackOnlyActualSuccess() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await completedTask(fixture)
        let analytics = SpyAnalyticsTracker()
        var shouldFail = true
        var saved = false
        let manager = HighlightTaskManager(store: fixture.storeFixture.store, fileStore: fixture.files,
            runner: fixture.runner, validateSource: { _ in }, saveVideo: { _ in
                if shouldFail { throw VideoClipPhotoLibraryError.accessDenied }
                saved = true
            }, analytics: analytics)
        await manager.load()
        do { try await manager.saveToPhotoLibrary(taskID: task.id); XCTFail("Expected denied save") } catch {}
        XCTAssertEqual(analytics.events.map(\.rawValue), ["highlight_save_started", "highlight_save_failed"])
        XCTAssertEqual(analytics.records.last?.stage, .permission)
        XCTAssertEqual(analytics.records.last?.reason, .permissionDenied)
        XCTAssertEqual(manager.task(task.id)?.currentOutput?.photoLibrarySaveErrorCode, .saveFailed)
        XCTAssertEqual(manager.task(task.id)?.configurationRevision, 1)
        shouldFail = false
        try await manager.saveToPhotoLibrary(taskID: task.id)
        XCTAssertTrue(saved)
        XCTAssertEqual(analytics.events.map(\.rawValue), ["highlight_save_started", "highlight_save_failed", "highlight_save_started", "highlight_save_succeeded"])
        XCTAssertNotNil(manager.task(task.id)?.currentOutput?.photoLibrarySavedAt)
        XCTAssertNil(manager.task(task.id)?.currentOutput?.photoLibrarySaveErrorCode)
        XCTAssertEqual(manager.task(task.id)?.configurationRevision, 1)
    }

    func testOldOutputCleanupFailureDoesNotRollBackCommittedNewOutput() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await completedTask(fixture)
        let oldURL = try fixture.manager.playbackURL(taskID: task.id)
        let oldDirectory = oldURL.deletingLastPathComponent()
        let protectedDirectory = fixture.storeFixture.directory.appendingPathComponent("protected-output")
        try FileManager.default.moveItem(at: oldDirectory, to: protectedDirectory)
        try FileManager.default.createSymbolicLink(at: oldDirectory, withDestinationURL: protectedDirectory)
        try await fixture.manager.restart(taskID: task.id)
        await waitFor { fixture.runner.executions.count == 2 }
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        let newURL = try fixture.manager.playbackURL(taskID: task.id)
        XCTAssertNotEqual(newURL, oldURL)
        XCTAssertEqual(fixture.manager.task(task.id)?.state, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedDirectory.appendingPathComponent("highlight.mov").path))
        XCTAssertEqual(fixture.analytics.events.map(\.rawValue), ["highlight_generate_started", "highlight_generate_succeeded", "highlight_generate_started", "highlight_generate_succeeded"])
    }

    func testActualPhotoSaveStillEmitsSuccessIfSubsequentStatusWriteFails() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await completedTask(fixture)
        let store = HighlightTaskStore(fileURL: fixture.storeFixture.fileURL, atomicWrite: { data, url in
            let document = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: data)
            if document.tasks.first?.currentOutput?.photoLibrarySavedAt != nil { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let analytics = SpyAnalyticsTracker()
        var actualSaveCompleted = false
        let manager = HighlightTaskManager(store: store, fileStore: fixture.files, runner: fixture.runner,
            validateSource: { _ in }, saveVideo: { _ in actualSaveCompleted = true }, analytics: analytics)
        await manager.load()
        do { try await manager.saveToPhotoLibrary(taskID: task.id); XCTFail("Expected local status failure") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .persistence) }
        XCTAssertTrue(actualSaveCompleted)
        XCTAssertEqual(analytics.events.map(\.rawValue), ["highlight_save_started", "highlight_save_succeeded", "highlight_save_state_failed"])
        XCTAssertEqual(Set(analytics.records.compactMap(\.operationID)).count, 1)
        XCTAssertEqual(analytics.records.last?.stage, .localState)
        XCTAssertEqual(analytics.records.last?.reason, .stateUpdateFailed)
        XCTAssertNil(manager.task(task.id)?.currentOutput?.photoLibrarySavedAt)
        XCTAssertEqual(manager.task(task.id)?.configurationRevision, 1)
    }

    func testCorruptDocumentDoesNotCleanUnreferencedTaskFiles() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await completedTask(fixture)
        let url = try fixture.manager.playbackURL(taskID: task.id)
        try Data("corrupt".utf8).write(to: fixture.storeFixture.fileURL)
        await fixture.manager.load()
        XCTAssertNotNil(fixture.manager.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPhotoWriteCancellationAndMissingFileAreSeparateResults() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await completedTask(fixture)
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightTaskManager(store: fixture.storeFixture.store, fileStore: fixture.files,
            runner: fixture.runner, validateSource: { _ in }, saveVideo: { _ in throw CancellationError() }, analytics: analytics)
        await manager.load()
        do { try await manager.saveToPhotoLibrary(taskID: task.id); XCTFail("Cancel") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .photoSaveFailed) }
        let outputURL = try manager.playbackURL(taskID: task.id)
        try FileManager.default.removeItem(at: outputURL)
        do { try await manager.saveToPhotoLibrary(taskID: task.id); XCTFail("Missing output") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .photoSaveFailed) }
        XCTAssertEqual(analytics.events, [.highlightSaveStarted, .highlightSaveCancelled, .highlightSaveStarted, .highlightSaveFailed])
        XCTAssertEqual(analytics.records.map(\.stage), [.validation, .photosWrite, .validation, .validation])
        XCTAssertEqual(analytics.records.map(\.reason), [nil, .cancelled, nil, .missingOutput])
        XCTAssertEqual(Set(analytics.records.compactMap(\.operationID)).count, 2)
    }

    func testSaveReentryDoesNotCreateAnotherAttempt() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await completedTask(fixture)
        let analytics = SpyAnalyticsTracker()
        var continuation: CheckedContinuation<Void, Never>?
        let manager = HighlightTaskManager(store: fixture.storeFixture.store, fileStore: fixture.files,
            runner: fixture.runner, validateSource: { _ in }, saveVideo: { _ in
                await withCheckedContinuation { continuation = $0 }
            }, analytics: analytics)
        await manager.load()
        let saving = Task { try await manager.saveToPhotoLibrary(taskID: task.id) }
        await waitFor { continuation != nil }
        do { try await manager.saveToPhotoLibrary(taskID: task.id); XCTFail("Busy") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .busy) }
        XCTAssertEqual(analytics.events, [.highlightSaveStarted])
        continuation?.resume()
        try await saving.value
        XCTAssertEqual(analytics.events, [.highlightSaveStarted, .highlightSaveSucceeded])
        XCTAssertEqual(Set(analytics.records.compactMap(\.operationID)).count, 1)
    }

    private func completedTask(_ fixture: TaskManagerFixture) async throws -> HighlightTask {
        let task = try await fixture.create()
        try await fixture.manager.start(taskID: task.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        return try XCTUnwrap(fixture.manager.task(task.id))
    }

    private func selection(_ url: URL) -> SelectedTrainingVideo {
        SelectedTrainingVideo(id: url.absoluteString, recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60)
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for runner")
    }
}

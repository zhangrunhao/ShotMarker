@testable import ShotMarker
import XCTest

final class HighlightTaskManagerTests: XCTestCase {
    func testReloadDuringActiveRenderDoesNotNormalizeOrCleanRunningExecution() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        await fixture.manager.load()
        let task = try await fixture.create()
        try await fixture.manager.start(taskID: task.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        await fixture.manager.load()
        XCTAssertEqual(fixture.manager.task(task.id)?.state, .running)
        XCTAssertNotNil(fixture.manager.task(task.id)?.activeExecution)
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        XCTAssertEqual(fixture.manager.task(task.id)?.state, .completed)
    }

    func testBackgroundForegroundDuringSourceValidationCannotStartPreBackgroundRequest() async throws {
        let storage = try TaskStoreFixture()
        defer { storage.cleanup() }
        let files = HighlightTaskFileStore(baseDirectory: storage.directory)
        let runner = ControlledHighlightRenderRunner()
        var continuation: CheckedContinuation<Void, Never>?
        let manager = HighlightTaskManager(store: storage.store, fileStore: files, runner: runner,
            validateSource: { _ in await withCheckedContinuation { continuation = $0 } })
        let task = try await manager.createTask(session: HighlightTaskTestFixture.session,
            selectedVideos: TaskManagerFixture.videos, settings: .default)
        let start = Task { try await manager.start(taskID: task.id, expectedRevision: 1) }
        await waitFor { continuation != nil }
        manager.enterBackground()
        await manager.stopAllExecutions()
        manager.enterForeground()
        continuation?.resume()
        do { try await start.value; XCTFail("A pre-background start request must stay invalidated") } catch {}
        if manager.task(task.id)?.activeExecution != nil {
            await waitFor { runner.executions.count == 1 }
            try await manager.stop(taskID: task.id)
            runner.finishNextSuccessfully()
        }
        await manager.waitUntilIdle()
        XCTAssertEqual(runner.executions.count, 0)
    }

    func testCreateIsVisibleBeforeRenderAndRepeatedCreationIDDoesNotDuplicate() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        await fixture.manager.load()
        let id = UUID()
        let first = try await fixture.create(id: id)
        let repeated = try await fixture.create(id: id)
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(fixture.manager.tasks.count, 1)
        XCTAssertEqual(first.state, .reviewing)
        XCTAssertEqual(fixture.runner.executions.count, 0)
    }

    func testStopPreservesTaskAndKeepsSerialSlotUntilUncooperativeRunnerExits() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let first = try await fixture.create()
        let second = try await fixture.create()
        try await fixture.manager.start(taskID: first.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        try await fixture.manager.start(taskID: second.id, expectedRevision: 1)
        try await fixture.manager.stop(taskID: first.id)
        XCTAssertEqual(fixture.manager.task(first.id)?.state, .stopped)
        XCTAssertEqual(fixture.runner.executions.count, 1)
        fixture.runner.finishNextSuccessfully()
        await waitFor { fixture.runner.executions.count == 2 }
        XCTAssertNil(fixture.manager.task(first.id)?.currentOutput)
        XCTAssertEqual(fixture.manager.task(first.id)?.state, .stopped)
        try await fixture.manager.stop(taskID: second.id)
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        XCTAssertEqual(fixture.analytics.events.map(\.rawValue), ["highlight_generate_started", "highlight_generate_started", "highlight_generate_cancelled", "highlight_generate_cancelled"])
    }

    func testQueuedStopNeverStartsAndBackgroundStopsAllWithoutAutomaticRestart() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let first = try await fixture.create()
        let queued = try await fixture.create()
        try await fixture.manager.start(taskID: first.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        try await fixture.manager.start(taskID: queued.id, expectedRevision: 1)
        fixture.manager.enterBackground()
        await waitFor { fixture.manager.tasks.allSatisfy { $0.state == .stopped } }
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        fixture.manager.enterForeground()
        XCTAssertEqual(fixture.runner.executions.count, 1)
        XCTAssertTrue(fixture.manager.tasks.allSatisfy { $0.currentOutput == nil })
        XCTAssertEqual(fixture.analytics.events.filter { $0 == .highlightGenerateCancelled }.count, 2)
        XCTAssertEqual(fixture.analytics.records.filter { $0.event == .highlightGenerateCancelled }.map(\.reason), [.backgrounded, .backgrounded])
    }

    func testSuccessfulReplacementDeletesOldOnlyAfterCommitAndTracksSuccess() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        try await fixture.manager.start(taskID: task.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        let old = try XCTUnwrap(fixture.manager.task(task.id)?.currentOutput)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try fixture.files.url(forRelativePath: old.relativePath).path))
        try await fixture.manager.restart(taskID: task.id)
        await waitFor { fixture.runner.executions.count == 2 }
        XCTAssertEqual(fixture.manager.task(task.id)?.allowedActions, [.stop])
        XCTAssertEqual(fixture.manager.task(task.id)?.currentOutput, old)
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        XCTAssertNotEqual(fixture.manager.task(task.id)?.currentOutput?.id, old.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try fixture.files.url(forRelativePath: old.relativePath).path))
        XCTAssertEqual(fixture.analytics.events.map(\.rawValue), ["highlight_generate_started", "highlight_generate_succeeded", "highlight_generate_started", "highlight_generate_succeeded"])
    }

    func testFailedRegenerationKeepsPreviousOutputAndChangedConfigurationRequiresReview() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        try await fixture.manager.start(taskID: task.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        let old = try XCTUnwrap(fixture.manager.task(task.id)?.currentOutput)
        try await fixture.manager.restart(taskID: task.id)
        await waitFor { fixture.runner.executions.count == 2 }
        fixture.runner.failNext()
        await fixture.manager.waitUntilIdle()
        XCTAssertEqual(fixture.manager.task(task.id)?.state, .failed)
        XCTAssertEqual(fixture.manager.task(task.id)?.currentOutput, old)
        var settings = task.clipSettings
        settings.markerLabelStyle.textOpacity = 0.3
        _ = try await fixture.manager.updateConfiguration(taskID: task.id, expectedRevision: 1,
            selectedVideos: TaskManagerFixture.videos, settings: settings)
        XCTAssertEqual(fixture.manager.task(task.id)?.state, .modified)
        do { try await fixture.manager.restart(taskID: task.id); XCTFail("Changed configuration requires review") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .mustReview) }
    }

    func testGenerateValidationFailureReasonsAndDedicatedAttemptIDs() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        do { try await fixture.manager.start(taskID: UUID(), expectedRevision: 1); XCTFail("Missing task") } catch {}
        do { try await fixture.manager.start(taskID: task.id, expectedRevision: 99); XCTFail("Stale revision") } catch {}
        fixture.manager.enterBackground()
        await fixture.manager.stopAllExecutions()
        do { try await fixture.manager.start(taskID: task.id, expectedRevision: 1); XCTFail("Background") } catch {}
        XCTAssertEqual(fixture.analytics.events, [.highlightGenerateStarted, .highlightGenerateFailed,
            .highlightGenerateStarted, .highlightGenerateFailed, .highlightGenerateStarted, .highlightGenerateFailed])
        XCTAssertEqual(fixture.analytics.records.map(\.reason), [nil, .invalidTask, nil, .revisionConflict, nil, .background])
        XCTAssertEqual(Set(fixture.analytics.records.compactMap(\.operationID)).count, 3)
        XCTAssertFalse(fixture.analytics.records.contains { $0.operationID == task.id })
        XCTAssertTrue(fixture.analytics.records.allSatisfy { $0.stage == .validation })
        XCTAssertEqual(fixture.runner.executions.count, 0)
    }

    func testSourceValidationFailureKeepsBusinessErrorAndTracksFailure() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightTaskManager(store: fixture.storeFixture.store, fileStore: fixture.files,
            runner: fixture.runner, validateSource: { _ in throw CocoaError(.fileReadNoSuchFile) }, analytics: analytics)
        await manager.load()
        do { try await manager.start(taskID: task.id, expectedRevision: 1); XCTFail("Missing source") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .sourceUnavailable) }
        XCTAssertEqual(analytics.events, [.highlightGenerateStarted, .highlightGenerateFailed])
        XCTAssertEqual(analytics.records.last?.reason, .sourceUnavailable)
        XCTAssertEqual(analytics.records.last?.stage, .validation)
        XCTAssertNil(manager.task(task.id)?.activeExecution)
    }

    func testQueuedStopAndLateRunnerCompletionHaveOneTerminalPerOperation() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let first = try await fixture.create()
        let queued = try await fixture.create()
        try await fixture.manager.start(taskID: first.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        try await fixture.manager.start(taskID: queued.id, expectedRevision: 1)
        try await fixture.manager.stop(taskID: queued.id)
        try await fixture.manager.stop(taskID: first.id)
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        XCTAssertEqual(fixture.analytics.events, [.highlightGenerateStarted, .highlightGenerateStarted,
            .highlightGenerateCancelled, .highlightGenerateCancelled])
        XCTAssertEqual(fixture.analytics.records.suffix(2).map(\.stage), [.queue, .export])
        XCTAssertEqual(fixture.analytics.records.suffix(2).map(\.reason), [.userCancelled, .userCancelled])
        let grouped = Dictionary(grouping: fixture.analytics.records, by: { $0.operationID })
        XCTAssertEqual(grouped.count, 2)
        XCTAssertTrue(grouped.values.allSatisfy { $0.count == 2 })
        XCTAssertEqual(fixture.runner.executions.count, 1)
        XCTAssertTrue(fixture.manager.tasks.allSatisfy { $0.currentOutput == nil })
    }

    func testBusyGenerateAttemptDoesNotStealRunningOperation() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        try await fixture.manager.start(taskID: task.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        do { try await fixture.manager.start(taskID: task.id, expectedRevision: 1); XCTFail("Busy") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .busy) }
        XCTAssertEqual(fixture.analytics.records.last?.reason, .busy)
        try await fixture.manager.stop(taskID: task.id)
        fixture.runner.finishNextSuccessfully()
        await fixture.manager.waitUntilIdle()
        XCTAssertEqual(fixture.analytics.events, [.highlightGenerateStarted, .highlightGenerateStarted,
            .highlightGenerateFailed, .highlightGenerateCancelled])
        XCTAssertEqual(fixture.analytics.records.first?.operationID, fixture.analytics.records.last?.operationID)
        XCTAssertNotEqual(fixture.analytics.records[0].operationID, fixture.analytics.records[1].operationID)
    }

    func testQueueWriteFailureReportsQueueAndPreservesBusinessError() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let failingStore = HighlightTaskStore(fileURL: fixture.storeFixture.fileURL, atomicWrite: { data, url in
            let document = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: data)
            if document.tasks.contains(where: { $0.activeExecution != nil }) { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightTaskManager(store: failingStore, fileStore: fixture.files, runner: fixture.runner,
            validateSource: { _ in }, analytics: analytics)
        await manager.load()
        do { try await manager.start(taskID: task.id, expectedRevision: 1); XCTFail("Queue write") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .persistence) }
        XCTAssertEqual(analytics.events, [.highlightGenerateStarted, .highlightGenerateFailed])
        XCTAssertEqual(analytics.records.last?.stage, .queue)
        XCTAssertEqual(analytics.records.last?.reason, .unknown)
        XCTAssertNil(manager.task(task.id)?.activeExecution)
        XCTAssertEqual(fixture.runner.executions.count, 0)
    }

    func testStopAllDoesNotMislabelCommittedSuccessWhileFinishCallbackIsDelayed() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let store = DelayedFinishHighlightTaskStore(base: fixture.storeFixture.store)
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightTaskManager(store: store, fileStore: fixture.files, runner: fixture.runner,
            validateSource: { _ in }, analytics: analytics)
        await manager.load()
        try await manager.start(taskID: task.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        fixture.runner.finishNextSuccessfully()
        for _ in 0..<500 {
            if await store.isFinishPending { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let isPending = await store.isFinishPending
        XCTAssertTrue(isPending)
        let stopping = Task { await manager.stopAllExecutions() }
        for _ in 0..<500 {
            if await store.stopAllCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        // Let stopAll consume the store result before delivering the committed finish callback.
        for _ in 0..<20 { await Task.yield() }
        await store.releaseFinish()
        await stopping.value
        await manager.waitUntilIdle()
        XCTAssertEqual(manager.task(task.id)?.state, .completed)
        XCTAssertEqual(analytics.events, [.highlightGenerateStarted, .highlightGenerateSucceeded])
    }

    func testBackgroundDuringCommittedInstallStillTracksQueuedCancellation() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let store = DelayedFinishHighlightTaskStore(base: fixture.storeFixture.store, gate: .installation)
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightTaskManager(store: store, fileStore: fixture.files, runner: fixture.runner,
            validateSource: { _ in }, analytics: analytics)
        await manager.load()
        let starting = Task { try await manager.start(taskID: task.id, expectedRevision: 1) }
        await waitForGate(store)
        manager.enterBackground()
        await manager.stopAllExecutions()
        await store.releaseFinish()
        try await starting.value
        XCTAssertEqual(manager.task(task.id)?.state, .stopped)
        XCTAssertEqual(fixture.runner.executions.count, 0)
        XCTAssertEqual(analytics.events, [.highlightGenerateStarted, .highlightGenerateCancelled])
        XCTAssertEqual(analytics.records.last?.stage, .queue)
        XCTAssertEqual(analytics.records.last?.reason, .backgrounded)
        XCTAssertEqual(Set(analytics.records.compactMap(\.operationID)).count, 1)
    }

    func testCommittedStopWinsOverLateOrdinaryRunnerFailure() async throws {
        for gate in [DelayedFinishHighlightTaskStore.Gate.stop, .stopAll, .stopWithFailedFinish] {
            let fixture = try TaskManagerFixture()
            defer { fixture.cleanup() }
            let task = try await fixture.create()
            let store = DelayedFinishHighlightTaskStore(base: fixture.storeFixture.store, gate: gate)
            let analytics = SpyAnalyticsTracker()
            let manager = HighlightTaskManager(store: store, fileStore: fixture.files, runner: fixture.runner,
                validateSource: { _ in }, analytics: analytics)
            await manager.load()
            try await manager.start(taskID: task.id, expectedRevision: 1)
            await waitFor { fixture.runner.executions.count == 1 }
            let stopping = Task {
                if gate != .stopAll { try await manager.stop(taskID: task.id) }
                else { await manager.stopAllExecutions() }
            }
            await waitForGate(store)
            fixture.runner.failNext()
            await manager.waitUntilIdle()
            await store.releaseFinish()
            try await stopping.value
            XCTAssertEqual(manager.task(task.id)?.state, .stopped)
            XCTAssertEqual(analytics.events, [.highlightGenerateStarted, .highlightGenerateCancelled])
            XCTAssertEqual(analytics.records.last?.reason, gate == .stopAll ? .cancelled : .userCancelled)
            XCTAssertEqual(Set(analytics.records.compactMap(\.operationID)).count, 1)
        }
    }

    func testFailedFinishPersistenceStillReportsObservedFailureAndReleasesOperation() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let store = HighlightTaskStore(fileURL: fixture.storeFixture.fileURL, atomicWrite: { data, url in
            let document = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: data)
            if document.tasks.contains(where: { $0.lastGenerationResult?.status == .failed }) { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightTaskManager(store: store, fileStore: fixture.files, runner: fixture.runner,
            validateSource: { _ in }, analytics: analytics)
        await manager.load()
        try await manager.start(taskID: task.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        fixture.runner.failNext()
        await manager.waitUntilIdle()
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertEqual(analytics.events, [.highlightGenerateStarted, .highlightGenerateFailed])
        XCTAssertEqual(analytics.records.last?.reason, .sourceUnavailable)
        try await manager.stop(taskID: task.id)
        XCTAssertEqual(analytics.events, [.highlightGenerateStarted, .highlightGenerateFailed])
    }

    func testFailedStopAndFailedFinishReleaseDeferredActualFailure() async throws {
        let fixture = try TaskManagerFixture()
        defer { fixture.cleanup() }
        let task = try await fixture.create()
        let store = DelayedFinishHighlightTaskStore(base: fixture.storeFixture.store, gate: .failedStopAll)
        let analytics = SpyAnalyticsTracker()
        let manager = HighlightTaskManager(store: store, fileStore: fixture.files, runner: fixture.runner,
            validateSource: { _ in }, analytics: analytics)
        await manager.load()
        try await manager.start(taskID: task.id, expectedRevision: 1)
        await waitFor { fixture.runner.executions.count == 1 }
        let stopping = Task { await manager.stopAllExecutions() }
        await waitForGate(store)
        fixture.runner.failNext()
        await manager.waitUntilIdle()
        XCTAssertEqual(analytics.events, [.highlightGenerateStarted])
        await store.releaseFinish()
        await stopping.value
        XCTAssertEqual(analytics.events, [.highlightGenerateStarted, .highlightGenerateFailed])
        XCTAssertEqual(analytics.records.last?.stage, .export)
        XCTAssertEqual(analytics.records.last?.reason, .sourceUnavailable)
        XCTAssertNotNil(manager.errorMessage)
    }

    private func waitForGate(_ store: DelayedFinishHighlightTaskStore) async {
        for _ in 0..<500 {
            if await store.isFinishPending { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for committed store return gate")
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for observable state")
    }
}

@MainActor
final class ControlledHighlightRenderRunner: HighlightRenderRunning {
    private(set) var executions: [HighlightRenderExecution] = []
    private var pending: [(URL, CheckedContinuation<URL, Error>)] = []
    func run(execution: HighlightRenderExecution, outputURL: URL,
        onProgress: @escaping @MainActor (HighlightJobProgress) -> Void) async throws -> URL {
        executions.append(execution)
        return try await withCheckedThrowingContinuation { pending.append((outputURL, $0)) }
    }
    func finishNextSuccessfully() {
        guard !pending.isEmpty else { return }
        let (url, continuation) = pending.removeFirst()
        do { try Data("rendered".utf8).write(to: url); continuation.resume(returning: url) }
        catch { continuation.resume(throwing: error) }
    }
    func failNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().1.resume(throwing: HighlightTaskError.sourceUnavailable)
    }
    func finishWithMissingOutput() {
        guard !pending.isEmpty else { return }
        let (url, continuation) = pending.removeFirst()
        continuation.resume(returning: url)
    }
}

struct TaskManagerFixture {
    let storeFixture: TaskStoreFixture
    let files: HighlightTaskFileStore
    let runner = ControlledHighlightRenderRunner()
    let analytics = SpyAnalyticsTracker()
    let manager: HighlightTaskManager
    static let videos = [SelectedTrainingVideo(id: "fixture", recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60, reviewSourceIdentity: .photoLibraryAsset("fixture"))]
    init() throws {
        storeFixture = try TaskStoreFixture()
        files = HighlightTaskFileStore(baseDirectory: storeFixture.directory,
            temporaryDirectory: storeFixture.directory.appendingPathComponent("tmp"))
        manager = HighlightTaskManager(store: storeFixture.store, fileStore: files, runner: runner,
            validateSource: { _ in }, analytics: analytics)
    }
    func create(id: UUID = UUID()) async throws -> HighlightTask {
        try await manager.createTask(id: id, session: HighlightTaskTestFixture.session,
            selectedVideos: Self.videos, settings: .default)
    }
    func cleanup() { storeFixture.cleanup() }
}

private actor DelayedFinishHighlightTaskStore: HighlightTaskStoring {
    enum Gate { case success, installation, stop, stopAll, stopWithFailedFinish, failedStopAll }
    let base: HighlightTaskStore
    let gate: Gate
    private(set) var isFinishPending = false
    private(set) var stopAllCount = 0
    private var finishContinuation: CheckedContinuation<Void, Never>?
    init(base: HighlightTaskStore, gate: Gate = .success) { self.base = base; self.gate = gate }
    func loadForLaunch() async throws -> [HighlightTask] { try await base.loadForLaunch() }
    func load() async throws -> [HighlightTask] { try await base.load() }
    func create(_ task: HighlightTask) async throws { try await base.create(task) }
    func updateConfiguration(id: UUID, expectedRevision: Int, videos: [HighlightTaskVideo],
        settings: ClipSettings, items: [PersistedHighlightTaskClip]) async throws -> HighlightTask {
        try await base.updateConfiguration(id: id, expectedRevision: expectedRevision, videos: videos, settings: settings, items: items)
    }
    func installExecution(taskID: UUID, expectedRevision: Int, execution: HighlightRenderExecution) async throws -> HighlightTask {
        let result = try await base.installExecution(taskID: taskID, expectedRevision: expectedRevision, execution: execution)
        if gate == .installation { await holdReturn() }
        return result
    }
    func updateProgress(taskID: UUID, executionID: UUID, revision: Int, progress: HighlightJobProgress) async throws -> HighlightTask? {
        try await base.updateProgress(taskID: taskID, executionID: executionID, revision: revision, progress: progress)
    }
    func finishExecution(taskID: UUID, executionID: UUID, revision: Int,
        status: HighlightTaskGenerationResultStatus, errorCode: HighlightTaskGenerationErrorCode?,
        output: HighlightTaskOutput?) async throws -> HighlightTask? {
        if status == .failed && (gate == .stopWithFailedFinish || gate == .failedStopAll) { throw HighlightTaskError.persistence }
        let result = try await base.finishExecution(taskID: taskID, executionID: executionID, revision: revision,
            status: status, errorCode: errorCode, output: output)
        if (gate == .success && status == .succeeded) || ((gate == .stop || gate == .stopWithFailedFinish) && status == .stopped && result != nil) {
            await holdReturn()
        }
        return result
    }
    func stopAll() async throws -> [HighlightTask] {
        if gate == .failedStopAll {
            stopAllCount += 1
            await holdReturn()
            throw HighlightTaskError.persistence
        }
        let result = try await base.stopAll()
        stopAllCount += 1
        if gate == .stopAll { await holdReturn() }
        return result
    }
    func savePhotoResult(taskID: UUID, outputID: UUID, savedAt: Date?, errorCode: HighlightTaskPhotoSaveErrorCode?) async throws -> HighlightTask? {
        try await base.savePhotoResult(taskID: taskID, outputID: outputID, savedAt: savedAt, errorCode: errorCode)
    }
    func delete(id: UUID, expectedRevision: Int) async throws { try await base.delete(id: id, expectedRevision: expectedRevision) }
    private func holdReturn() async {
        isFinishPending = true
        await withCheckedContinuation { finishContinuation = $0 }
    }
    func releaseFinish() { finishContinuation?.resume(); finishContinuation = nil }
}

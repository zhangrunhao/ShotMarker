@testable import ShotMarker
import XCTest

final class HighlightTaskStoreTests: XCTestCase {
    func testSchemaTwoReadAndNoopStayUntouchedThenSignedWriteUpgradesAndSurvivesReload() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        let bytes = try JSONEncoder().encode(HighlightTaskStoreDocument(schemaVersion: 2, tasks: [task]))
        try bytes.write(to: fixture.fileURL)
        let loaded = try await fixture.store.loadForLaunch()
        XCTAssertEqual(loaded, [task])
        _ = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: task.clipSettings, items: task.reviewItems)
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
        let settings = ClipSettings(secondsBeforeMarker: 11, secondsAfterMarker: -2)
        let result = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos, settings: settings)
        let updated = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: settings, items: result.items)
        let execution = try HighlightTaskPlanner.execution(for: updated)
        _ = try await fixture.store.installExecution(taskID: task.id, expectedRevision: 2, execution: execution)
        let restored = try await HighlightTaskStore(fileURL: fixture.fileURL).load()
        XCTAssertEqual(restored[0].clipSettings, settings)
        XCTAssertEqual(restored[0].activeExecution?.snapshot.clipSettings, settings)
        let document = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: Data(contentsOf: fixture.fileURL))
        XCTAssertEqual(document.schemaVersion, 3)
    }

    func testInvalidOffsetWritePreservesExistingTaskBytes() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        try await fixture.store.create(task)
        let before = try Data(contentsOf: fixture.fileURL)
        do {
            _ = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
                videos: task.videos, settings: ClipSettings(secondsBeforeMarker: 0.2, secondsAfterMarker: 0.2),
                items: task.reviewItems)
            XCTFail("An invalid intermediate range must never be persisted")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .invalidTask) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
    }

    func testFramingOnlyCommitChangesRevisionAndPreservesOldOutputAndNilDistinction() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        var task = try HighlightTaskTestFixture.task()
        task.currentOutput = HighlightTaskTestFixture.output(task: task)
        let legacy = try JSONEncoder().encode(HighlightTaskStoreDocument(schemaVersion: 1, tasks: [task]))
        try legacy.write(to: fixture.fileURL)
        var items = task.reviewItems
        items[0].framing = .original
        let updated = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: task.clipSettings, items: items)
        XCTAssertEqual(updated.configurationRevision, 2)
        XCTAssertEqual(updated.currentOutput, task.currentOutput)
        XCTAssertTrue(updated.outputIsOutdated)
        let restored = try await HighlightTaskStore(fileURL: fixture.fileURL).load()
        XCTAssertEqual(restored[0].reviewItems[0].framing, .original)
        XCTAssertNil(restored[0].reviewItems[1].framing)
        var invalid = items
        invalid[0].framing = ClipFraming(scale: 2.25, centerX: 0.5, centerY: 0.5)
        let before = try Data(contentsOf: fixture.fileURL)
        do {
            _ = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 2,
                videos: task.videos, settings: task.clipSettings, items: invalid)
            XCTFail("Noncanonical persisted framing must be rejected")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .invalidTask) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
    }

    func testFailedSchemaOneUpgradePreservesOriginalBytes() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        let legacy = try JSONEncoder().encode(HighlightTaskStoreDocument(schemaVersion: 1, tasks: [task]))
        try legacy.write(to: fixture.fileURL)
        let failing = HighlightTaskStore(fileURL: fixture.fileURL,
            atomicWrite: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        var items = task.reviewItems
        items[0].framing = ClipFraming(scale: 2.2, centerX: 0.5, centerY: 0.5)
        do {
            _ = try await failing.updateConfiguration(id: task.id, expectedRevision: 1,
                videos: task.videos, settings: task.clipSettings, items: items)
            XCTFail("Expected write failure")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .persistence) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), legacy)
    }

    func testSchemaOneLoadAndNoopPreserveBytesAndSuccessfulEditUpgradesToThree() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        let legacy = try JSONEncoder().encode(HighlightTaskStoreDocument(schemaVersion: 1, tasks: [task]))
        try legacy.write(to: fixture.fileURL)
        let loaded = try await fixture.store.loadForLaunch()
        XCTAssertEqual(loaded, [task])
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), legacy)
        _ = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: task.clipSettings, items: task.reviewItems)
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), legacy)
        var items = task.reviewItems
        items[0].isIncluded = false
        let updated = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: task.clipSettings, items: items)
        XCTAssertEqual(updated.configurationRevision, 2)
        let document = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: Data(contentsOf: fixture.fileURL))
        XCTAssertEqual(document.schemaVersion, 3)
        XCTAssertEqual(document.tasks[0].reviewItems, items)
    }

    func testInvalidStoredFramingIsQuarantinedRatherThanIgnored() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        let encoded = try JSONEncoder().encode(HighlightTaskStoreDocument(schemaVersion: 1, tasks: [task]))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var tasks = try XCTUnwrap(root["tasks"] as? [[String: Any]])
        var items = try XCTUnwrap(tasks[0]["reviewItems"] as? [[String: Any]])
        items[0]["framing"] = ["scale": 99, "centerX": 0.5, "centerY": 0.5]
        tasks[0]["reviewItems"] = items
        root["tasks"] = tasks
        try JSONSerialization.data(withJSONObject: root).write(to: fixture.fileURL)
        do {
            _ = try await fixture.store.load()
            XCTFail("Invalid framing must not be silently discarded")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .corruptDocument) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testOutputCommitWriteFailurePreservesPriorOutputAndActiveExecutionForFailureHandling() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        try await fixture.store.create(task)
        let first = try HighlightTaskPlanner.execution(for: task)
        _ = try await fixture.store.installExecution(taskID: task.id, expectedRevision: 1, execution: first)
        let oldOutput = HighlightTaskTestFixture.output(task: task)
        _ = try await fixture.store.finishExecution(taskID: task.id, executionID: first.id, revision: 1, status: .succeeded, output: oldOutput)
        let second = try HighlightTaskPlanner.execution(for: task)
        _ = try await fixture.store.installExecution(taskID: task.id, expectedRevision: 1, execution: second)
        let before = try Data(contentsOf: fixture.fileURL)
        let failing = HighlightTaskStore(fileURL: fixture.fileURL, atomicWrite: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        do {
            _ = try await failing.finishExecution(taskID: task.id, executionID: second.id, revision: 1,
                status: .succeeded, output: HighlightTaskTestFixture.output(task: task))
            XCTFail("Expected output-reference write failure")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .persistence) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
        let loaded = try await fixture.store.load()
        XCTAssertEqual(loaded[0].currentOutput, oldOutput)
        XCTAssertEqual(loaded[0].activeExecution?.id, second.id)
    }

    func testCompletionWinsAgainstLateStopAndActiveConfigurationOrDeleteAreRejected() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        try await fixture.store.create(task)
        let execution = try HighlightTaskPlanner.execution(for: task)
        _ = try await fixture.store.installExecution(taskID: task.id, expectedRevision: 1, execution: execution)
        do { try await fixture.store.delete(id: task.id, expectedRevision: 1); XCTFail("Cannot delete active task") }
        catch { XCTAssertEqual(error as? HighlightTaskError, .busy) }
        do {
            _ = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
                videos: task.videos, settings: task.clipSettings, items: task.reviewItems)
            XCTFail("Cannot edit active task")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .busy) }
        let output = HighlightTaskTestFixture.output(task: task)
        _ = try await fixture.store.finishExecution(taskID: task.id, executionID: execution.id, revision: 1, status: .succeeded, output: output)
        let lateStop = try await fixture.store.finishExecution(taskID: task.id, executionID: execution.id, revision: 1, status: .stopped)
        XCTAssertNil(lateStop)
        let loaded = try await fixture.store.load()
        XCTAssertEqual(loaded[0].state, .completed)
        XCTAssertEqual(loaded[0].currentOutput, output)
    }

    func testRoundTripPreservesSnapshotWithoutOriginalTrainingIdentity() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        try await fixture.store.create(task)
        let loaded = try await HighlightTaskStore(fileURL: fixture.fileURL).loadForLaunch()
        XCTAssertEqual(loaded, [task])
        let root = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: Data(contentsOf: fixture.fileURL))
        XCTAssertEqual(root.schemaVersion, 3)
        XCTAssertEqual(root.tasks[0].trainingSnapshot.markers.map(\.sourceOrder), [0, 1, 2])
        XCTAssertTrue(Set(task.trainingSnapshot.markers.map(\.id)).isDisjoint(with: HighlightTaskTestFixture.session.events.map(\.id)))
    }

    func testConfigurationNoopAndMultipleFieldsIncrementOnlyOnceThenRejectStaleRevision() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        try await fixture.store.create(task)
        let before = try Data(contentsOf: fixture.fileURL)
        let unchanged = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: task.clipSettings, items: task.reviewItems)
        XCTAssertEqual(unchanged.configurationRevision, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
        var settings = task.clipSettings
        settings.markerLabelStyle.textOpacity = 0.5
        var items = task.reviewItems
        items[0].isIncluded = false
        let updated = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: settings, items: items)
        XCTAssertEqual(updated.configurationRevision, 2)
        XCTAssertEqual(updated.trainingSnapshot, task.trainingSnapshot)
        do {
            _ = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
                videos: task.videos, settings: task.clipSettings, items: task.reviewItems)
            XCTFail("Stale editor must not overwrite the committed configuration")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .revisionConflict) }
    }

    func testFailedAtomicWriteLeavesDiskUnchanged() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        try await fixture.store.create(task)
        let bytes = try Data(contentsOf: fixture.fileURL)
        let failing = HighlightTaskStore(fileURL: fixture.fileURL, atomicWrite: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        do { try await failing.delete(id: task.id, expectedRevision: 1); XCTFail("Expected write failure") } catch {}
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
    }

    func testStopWinsAgainstLateOutputAndLaunchStopsAllRemainingExecutions() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        try await fixture.store.create(task)
        let execution = try HighlightTaskPlanner.execution(for: task)
        _ = try await fixture.store.installExecution(taskID: task.id, expectedRevision: 1, execution: execution)
        let stopped = try await fixture.store.finishExecution(taskID: task.id, executionID: execution.id,
            revision: 1, status: .stopped)
        XCTAssertEqual(stopped?.state, .stopped)
        let late = try await fixture.store.finishExecution(taskID: task.id, executionID: execution.id,
            revision: 1, status: .succeeded, output: HighlightTaskTestFixture.output(task: task))
        XCTAssertNil(late)
        let second = try HighlightTaskPlanner.execution(for: task)
        _ = try await fixture.store.installExecution(taskID: task.id, expectedRevision: 1, execution: second)
        let recovered = try await HighlightTaskStore(fileURL: fixture.fileURL).loadForLaunch()
        XCTAssertNil(recovered[0].activeExecution)
        XCTAssertEqual(recovered[0].state, .stopped)
        XCTAssertEqual(recovered[0].lastGenerationResult?.executionID, second.id)
    }

    func testUnknownSchemaAndCorruptDocumentStayProtectedAcrossInstances() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let future = Data(#"{"schemaVersion":4,"tasks":[]}"#.utf8)
        try future.write(to: fixture.fileURL)
        do { _ = try await fixture.store.loadForLaunch(); XCTFail("Must protect future schema") } catch {}
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), future)
        try Data("broken".utf8).write(to: fixture.fileURL)
        do { _ = try await fixture.store.loadForLaunch(); XCTFail("Must report corrupt document") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        do { _ = try await HighlightTaskStore(fileURL: fixture.fileURL).loadForLaunch(); XCTFail("Unrecovered backup must protect files") } catch {}
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
        XCTAssertEqual(names.filter { $0.hasPrefix("highlight-tasks.corrupt-") }.count, 1)
    }

    func testActiveExecutionOnlyAllowsStopEvenWithAnOldOutput() throws {
        var task = try HighlightTaskTestFixture.task()
        task.currentOutput = HighlightTaskTestFixture.output(task: task)
        XCTAssertEqual(task.state, .completed)
        task.configurationRevision += 1
        XCTAssertEqual(task.state, .modified)
        XCTAssertFalse(task.canRegenerateDirectly)
        task.activeExecution = try HighlightTaskPlanner.execution(for: task)
        XCTAssertEqual(task.allowedActions, [.stop])
        task.activeExecution?.status = .running
        XCTAssertEqual(task.allowedActions, [.stop])
        XCTAssertTrue(task.outputIsOutdated)
    }
}

struct TaskStoreFixture {
    let directory: URL
    let fileURL: URL
    let store: HighlightTaskStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("highlight-tasks.json")
        store = HighlightTaskStore(fileURL: fileURL)
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

enum HighlightTaskTestFixture {
    static let session = TrainingSession(startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 160), events: [10.0, 12, 40].map {
            ShotMarkerEvent(markedAt: Date(timeIntervalSince1970: 100 + $0))
        })
    static func task() throws -> HighlightTask {
        try HighlightTaskPlanner.makeTask(id: UUID(), session: session, videos: [video()], settings: .default)
    }
    static func video() -> HighlightTaskVideo {
        HighlightTaskVideo(id: UUID(), sourceIdentity: .photoLibraryAsset("fixture"),
            recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60,
            source: .photoLibraryAsset(localIdentifier: "fixture"))
    }
    static func output(task: HighlightTask) -> HighlightTaskOutput {
        let id = UUID()
        return HighlightTaskOutput(id: id, relativePath: "HighlightTasks/\(task.id)/Outputs/\(id)/highlight.mov",
            configurationRevision: task.configurationRevision, generatedAt: Date())
    }
}

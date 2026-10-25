@testable import ShotMarker
import XCTest

@MainActor
final class HighlightTaskLabelPlacementTests: XCTestCase {
    private let placement = MarkerLabelPlacement(fontSizeRatio: 0.16, normalizedCenterX: 0.8, normalizedCenterY: 0.7)

    func testSchemaThreeNoopPreservesBytesAndPlacementCommitWritesFour() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        let bytes = try JSONEncoder().encode(HighlightTaskStoreDocument(schemaVersion: 3, tasks: [task]))
        try bytes.write(to: fixture.fileURL)
        _ = try await fixture.store.load()
        _ = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: task.clipSettings, items: task.reviewItems)
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
        var items = task.reviewItems
        items[0].markerLabelPlacement = placement
        let updated = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
            videos: task.videos, settings: task.clipSettings, items: items)
        XCTAssertEqual(updated.configurationRevision, 2)
        let restored = try await HighlightTaskStore(fileURL: fixture.fileURL).load()
        XCTAssertEqual(restored[0].reviewItems[0].markerLabelPlacement, placement)
        XCTAssertNil(restored[0].reviewItems[1].markerLabelPlacement)
        let document = try JSONDecoder().decode(HighlightTaskStoreDocument.self, from: Data(contentsOf: fixture.fileURL))
        XCTAssertEqual(document.schemaVersion, 4)
    }

    func testInvalidAndNullPlacementAreQuarantinedWithoutSilentDefault() async throws {
        let corrupt: [Any] = [NSNull(), ["fontSizeRatio": 0.1, "normalizedCenterX": 0.5],
            ["fontSizeRatio": "large", "normalizedCenterX": 0.5, "normalizedCenterY": 0.5],
            ["fontSizeRatio": 0.17, "normalizedCenterX": 0.5, "normalizedCenterY": 0.5],
            ["fontSizeRatio": 0.1, "normalizedCenterX": -0.1, "normalizedCenterY": 0.5]]
        for value in corrupt {
            let fixture = try TaskStoreFixture()
            defer { fixture.cleanup() }
            let task = try HighlightTaskTestFixture.task()
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(HighlightTaskStoreDocument(schemaVersion: 4, tasks: [task]))) as? [String: Any])
            var tasks = try XCTUnwrap(root["tasks"] as? [[String: Any]])
            var items = try XCTUnwrap(tasks[0]["reviewItems"] as? [[String: Any]])
            items[0]["markerLabelPlacement"] = value
            tasks[0]["reviewItems"] = items
            root["tasks"] = tasks
            try JSONSerialization.data(withJSONObject: root).write(to: fixture.fileURL)
            do { _ = try await fixture.store.load(); XCTFail("Corrupt placement must not become a task default") }
            catch { XCTAssertEqual(error as? HighlightTaskError, .corruptDocument) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        }
    }

    func testInvalidPlacementWriteAndDiskFailurePreserveExistingBytesAndRevision() async throws {
        let fixture = try TaskStoreFixture()
        defer { fixture.cleanup() }
        let task = try HighlightTaskTestFixture.task()
        try await fixture.store.create(task)
        let before = try Data(contentsOf: fixture.fileURL)
        var items = task.reviewItems
        items[0].markerLabelPlacement = MarkerLabelPlacement(fontSizeRatio: 0.03, normalizedCenterX: 0.5, normalizedCenterY: 0.5)
        do {
            _ = try await fixture.store.updateConfiguration(id: task.id, expectedRevision: 1,
                videos: task.videos, settings: task.clipSettings, items: items)
            XCTFail("Invalid placement must not be normalized during persistence")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .invalidTask) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
        items[0].markerLabelPlacement = placement
        let failing = HighlightTaskStore(fileURL: fixture.fileURL,
            atomicWrite: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        do {
            _ = try await failing.updateConfiguration(id: task.id, expectedRevision: 1,
                videos: task.videos, settings: task.clipSettings, items: items)
            XCTFail("Expected write failure")
        } catch { XCTAssertEqual(error as? HighlightTaskError, .persistence) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), before)
        let restored = try await fixture.store.load()
        XCTAssertEqual(restored[0].configurationRevision, 1)
        XCTAssertNil(restored[0].reviewItems[0].markerLabelPlacement)
    }

    func testExecutionCapturesLayoutAndOpacityWhileConfigurationReplanningPreservesOnlyConfirmedOverrides() throws {
        var task = try HighlightTaskTestFixture.task()
        task.reviewItems[0].confirmationState = .confirmed
        task.reviewItems[0].markerLabelPlacement = placement
        task.clipSettings.markerLabelStyle.textOpacity = 0.3
        let execution = try HighlightTaskPlanner.execution(for: task)
        XCTAssertEqual(execution.snapshot.segments[0].markerLabelPlacement, placement)
        XCTAssertEqual(execution.snapshot.segments[1].markerLabelPlacement,
            MarkerLabelPlacement(fontSizeRatio: 0.1, normalizedCenterX: 0.15, normalizedCenterY: 0.1))
        task.clipSettings.markerLabelStyle.textOpacity = 0.9
        task.clipSettings.markerLabelStyle.fontSizeRatio = 0.04
        XCTAssertEqual(execution.snapshot.clipSettings.markerLabelStyle.textOpacity, 0.3)
        var settings = task.clipSettings
        settings.secondsBeforeMarker = 3
        let replanned = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos, settings: settings)
        XCTAssertEqual(replanned.items[0].markerLabelPlacement, placement)
        XCTAssertNil(replanned.items[1].markerLabelPlacement)
        let reset = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos, settings: settings, resetAll: true)
        XCTAssertTrue(reset.items.allSatisfy { $0.markerLabelPlacement == nil })
    }
}

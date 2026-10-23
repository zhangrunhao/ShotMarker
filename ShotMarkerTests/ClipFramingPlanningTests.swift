@testable import ShotMarker
import XCTest

final class ClipFramingPlanningTests: XCTestCase {
    func testDifferentFramingPreservesCompleteOverlappingSegmentsAndTheirNumbering() throws {
        var task = try overlappingTask()
        task.reviewItems[0].framing = ClipFraming(scale: 2.2, centerX: 0.4, centerY: 0.4)
        task.reviewItems[1].framing = ClipFraming(scale: 3, centerX: 0.6, centerY: 0.6)
        let draft = try HighlightTaskPlanner.reviewDraft(for: task)
        let summary = try HighlightClipReviewPlanner.makeSummary(items: draft.items,
            videos: task.videos.map(\.selectedTrainingVideo))
        XCTAssertEqual(summary.finalSegmentCount, 2)
        XCTAssertEqual(summary.finalSegments.map(\.start), [1, 10])
        XCTAssertEqual(summary.finalSegments.map(\.duration), [15, 15])
        XCTAssertEqual(summary.totalDuration, 30)
        XCTAssertEqual(summary.finalSegments.map(\.markerNumberLowerBound), [1, 3])
        XCTAssertEqual(summary.finalSegments.map(\.markerNumberUpperBound), [2, 3])
        XCTAssertTrue(summary.mergingItemIDs.isEmpty)
        XCTAssertEqual(summary.finalSegments.map(\.framing), task.reviewItems.compactMap(\.framing))
        let execution = try HighlightTaskPlanner.execution(for: task)
        XCTAssertEqual(execution.snapshot.segments.map(\.highlightClipSegment.framing),
            task.reviewItems.compactMap(\.framing))
    }

    func testMissingAndExplicitOriginalFramingMergeButRemainDistinctWhenPersisted() throws {
        var task = try overlappingTask()
        task.reviewItems[1].framing = .original
        let draft = try HighlightTaskPlanner.reviewDraft(for: task)
        XCTAssertNil(draft.items[0].framing)
        XCTAssertEqual(draft.items[1].framing, .original)
        XCTAssertNil(try HighlightTaskPlanner.persisted(draft.items[0]).framing)
        XCTAssertEqual(try HighlightTaskPlanner.persisted(draft.items[1]).framing, .original)
        let execution = try HighlightTaskPlanner.execution(for: task)
        XCTAssertEqual(execution.snapshot.segments.count, 1)
        XCTAssertEqual(execution.snapshot.segments[0].duration, 24)
        XCTAssertEqual(execution.snapshot.segments[0].framing, .original)
    }

    func testIdenticalZoomedFramingMergesAndSurvivesRenderConversion() throws {
        var task = try overlappingTask()
        let framing = ClipFraming(scale: 2.8, centerX: 0.5, centerY: 0.6)
        task.reviewItems[0].framing = framing
        task.reviewItems[1].framing = framing
        let execution = try HighlightTaskPlanner.execution(for: task)
        XCTAssertEqual(execution.snapshot.segments.count, 1)
        XCTAssertEqual(execution.snapshot.segments[0].framing, framing)
        XCTAssertEqual(execution.snapshot.segments[0].highlightClipSegment.framing, framing)
    }

    func testSafeConfirmedFramingSurvivesSettingsAndSameSourceButResetAndReplacementClearIt() throws {
        var task = try HighlightTaskTestFixture.task()
        let framing = ClipFraming(scale: 2.2, centerX: 0.4, centerY: 0.6)
        task.reviewItems[0].framing = framing
        task.reviewItems[0].confirmationState = .confirmed
        var settings = task.clipSettings
        settings.markerLabelStyle.textOpacity = 0.1
        XCTAssertEqual(try HighlightTaskPlanner.reconcile(task: task, videos: task.videos,
            settings: settings).items[0].framing, framing)
        settings.secondsBeforeMarker = 3
        XCTAssertEqual(try HighlightTaskPlanner.reconcile(task: task, videos: task.videos,
            settings: settings).items[0].framing, framing)
        var sameSource = task.videos[0]
        sameSource = HighlightTaskVideo(id: UUID(), sourceIdentity: sameSource.sourceIdentity,
            recordedStartAt: sameSource.recordedStartAt, duration: sameSource.duration, source: sameSource.source)
        XCTAssertEqual(try HighlightTaskPlanner.reconcile(task: task, videos: [sameSource],
            settings: task.clipSettings).items[0].framing, framing)
        let reset = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos,
            settings: task.clipSettings, resetAll: true)
        XCTAssertTrue(reset.items.allSatisfy { $0.framing == nil })
        let replacement = HighlightTaskVideo(id: UUID(), sourceIdentity: .photoLibraryAsset("replacement"),
            recordedStartAt: task.videos[0].recordedStartAt, duration: 60,
            source: .photoLibraryAsset(localIdentifier: "replacement"))
        let replaced = try HighlightTaskPlanner.reconcile(task: task, videos: [replacement], settings: task.clipSettings)
        XCTAssertEqual(replaced.resetConfirmationCount, 1)
        XCTAssertTrue(replaced.items.allSatisfy { $0.framing == nil })
    }

    func testReviewAndExecutionValidationRejectInvalidFramingIncludingExcludedItems() throws {
        var task = try HighlightTaskTestFixture.task()
        task.reviewItems[0].framing = ClipFraming(scale: 99, centerX: 0.5, centerY: 0.5)
        task.reviewItems[0].isIncluded = false
        XCTAssertThrowsError(try HighlightTaskValidation.validate(task))
        var draft = try HighlightTaskPlanner.reviewDraft(for: HighlightTaskTestFixture.task())
        draft.items[0].framing = ClipFraming(scale: 2.21, centerX: 0.5, centerY: 0.5)
        draft.items[0].isIncluded = false
        XCTAssertThrowsError(try HighlightClipReviewPlanner.makeSummary(items: draft.items,
            videos: [SelectedTrainingVideo(id: draft.items[0].videoID,
                recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60)]))
        task = try HighlightTaskTestFixture.task()
        let execution = try HighlightTaskPlanner.execution(for: task)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(execution)) as? [String: Any])
        var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        var segments = try XCTUnwrap(snapshot["segments"] as? [[String: Any]])
        segments[0]["framing"] = ["scale": 4.5, "centerX": 0.5, "centerY": 0.5]
        snapshot["segments"] = segments
        object["snapshot"] = snapshot
        task.activeExecution = try JSONDecoder().decode(HighlightRenderExecution.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try HighlightTaskValidation.validate(task))
        XCTAssertThrowsError(try HighlightClipReviewPlanner.validateConfirmedSegments(task.activeExecution!.snapshot.segments,
            videos: task.videos.map(\.selectedTrainingVideo), validMarkerIDs: Set(task.trainingSnapshot.markers.map(\.id))))
    }

    func testExplicitNullFramingInExecutionSnapshotIsNotTreatedAsLegacyMissingField() throws {
        let task = try HighlightTaskTestFixture.task()
        let execution = try HighlightTaskPlanner.execution(for: task)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(execution)) as? [String: Any])
        var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        var segments = try XCTUnwrap(snapshot["segments"] as? [[String: Any]])
        segments[0]["framing"] = NSNull()
        snapshot["segments"] = segments
        object["snapshot"] = snapshot
        XCTAssertThrowsError(try JSONDecoder().decode(HighlightRenderExecution.self,
            from: JSONSerialization.data(withJSONObject: object)))
    }

    func testLegacyExecutionSnapshotMissingFramingDecodesAsOriginal() throws {
        let task = try HighlightTaskTestFixture.task()
        let execution = try HighlightTaskPlanner.execution(for: task)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(execution)) as? [String: Any])
        var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        var segments = try XCTUnwrap(snapshot["segments"] as? [[String: Any]])
        for index in segments.indices { segments[index].removeValue(forKey: "framing") }
        snapshot["segments"] = segments
        object["snapshot"] = snapshot
        let restored = try JSONDecoder().decode(HighlightRenderExecution.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.snapshot.segments.map(\.framing), [.original, .original])
        var restoredTask = task
        restoredTask.activeExecution = restored
        XCTAssertNoThrow(try HighlightTaskValidation.validate(restoredTask))
    }

    private func overlappingTask() throws -> HighlightTask {
        var task = try HighlightTaskTestFixture.task()
        task.reviewItems[1].start = 10
        task.reviewItems[1].duration = 15
        return task
    }
}

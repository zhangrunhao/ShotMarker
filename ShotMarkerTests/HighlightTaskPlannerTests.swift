@testable import ShotMarker
import XCTest

final class HighlightTaskPlannerTests: XCTestCase {
    func testSignedAndZeroDefaultsBecomeExactExecutionRanges() throws {
        let video = HighlightTaskTestFixture.video()
        let session = TrainingSession(startedAt: video.recordedStartAt,
            endedAt: video.recordedEndAtForTest,
            events: [ShotMarkerEvent(markedAt: video.recordedStartAt.addingTimeInterval(30))])
        for (before, after, start, duration) in [(11.0, -2.0, 19.0, 9.0), (-2, 11, 32, 9),
                                                (0, 4, 30, 4), (4, 0, 26, 4)] {
            let settings = ClipSettings(secondsBeforeMarker: before, secondsAfterMarker: after)
            let task = try HighlightTaskPlanner.makeTask(id: UUID(), session: session, videos: [video], settings: settings)
            let execution = try HighlightTaskPlanner.execution(for: task)
            XCTAssertEqual(execution.snapshot.clipSettings, settings)
            XCTAssertEqual(execution.snapshot.segments.count, 1)
            XCTAssertEqual(execution.snapshot.segments[0].start, start)
            XCTAssertEqual(execution.snapshot.segments[0].duration, duration)
        }
    }

    func testInvalidDefaultsAreRejectedEvenWhenConfirmedItemsNeedNoReplanning() throws {
        let task = try HighlightTaskTestFixture.task()
        for (before, after) in [(0.0, 0.0), (2, -3), (0.4, 0.4), (21, 2), (-21, 20),
                                (2, 21), (20, -21), (.nan, 2), (2, .infinity)] {
            let settings = ClipSettings(secondsBeforeMarker: before, secondsAfterMarker: after)
            XCTAssertThrowsError(try HighlightTaskPlanner.makeTask(id: UUID(),
                session: HighlightTaskTestFixture.session, videos: task.videos, settings: settings))
            var invalid = task
            invalid.clipSettings = settings
            XCTAssertThrowsError(try HighlightTaskPlanner.reconcile(task: invalid, videos: invalid.videos, settings: settings))
        }
    }

    func testOffsetChangeOutsideSourcePreservesConfirmedRangeExclusionAndFraming() throws {
        var task = try HighlightTaskTestFixture.task()
        task.reviewItems[0].confirmationState = .confirmed
        task.reviewItems[0].start = 4
        task.reviewItems[0].duration = 5
        task.reviewItems[0].isIncluded = false
        task.reviewItems[0].framing = ClipFraming(scale: 2.2, centerX: 0.5, centerY: 0.5)
        let saved = task.reviewItems[0]
        let settings = ClipSettings(secondsBeforeMarker: 20, secondsAfterMarker: -19)
        let result = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos, settings: settings)
        XCTAssertEqual(result.resetConfirmationCount, 0)
        XCTAssertEqual(result.items[0], saved)
        XCTAssertEqual(result.items[1].start, 20)
        XCTAssertEqual(result.items[1].duration, 1)
        XCTAssertEqual(result.items[1].confirmationState, .defaultValue)
    }

    func testAllNewDefaultsOutsideSourceStillPreserveAvailableConfirmation() throws {
        let video = HighlightTaskTestFixture.video()
        let session = TrainingSession(startedAt: video.recordedStartAt,
            endedAt: video.recordedEndAtForTest,
            events: [ShotMarkerEvent(markedAt: video.recordedStartAt.addingTimeInterval(10))])
        var task = try HighlightTaskPlanner.makeTask(id: UUID(), session: session, videos: [video], settings: .default)
        task.reviewItems[0].confirmationState = .confirmed
        task.reviewItems[0].framing = ClipFraming(scale: 3, centerX: 0.5, centerY: 0.5)
        let result = try HighlightTaskPlanner.reconcile(task: task, videos: [video],
            settings: ClipSettings(secondsBeforeMarker: 20, secondsAfterMarker: -19))
        XCTAssertEqual(result.items, task.reviewItems)
        XCTAssertEqual(result.resetConfirmationCount, 0)
    }

    func testSignedDefaultIntersectionKeepsExistingMinimumDurationPolicy() throws {
        let video = HighlightTaskTestFixture.video()
        let session = TrainingSession(startedAt: video.recordedStartAt,
            endedAt: video.recordedEndAtForTest,
            events: [ShotMarkerEvent(markedAt: video.recordedStartAt.addingTimeInterval(2.5))])
        let task = try HighlightTaskPlanner.makeTask(id: UUID(), session: session, videos: [video],
            settings: ClipSettings(secondsBeforeMarker: 11, secondsAfterMarker: -2))
        XCTAssertEqual(task.reviewItems[0].start, 0)
        XCTAssertEqual(task.reviewItems[0].duration, 1)
    }
    func testShortVideoUsesWholeSourceAndCanGenerateAtExactMediaBoundary() throws {
        let video = HighlightTaskVideo(id: UUID(), sourceIdentity: .photoLibraryAsset("short"),
            recordedStartAt: Date(timeIntervalSince1970: 100), duration: 0.55,
            source: .photoLibraryAsset(localIdentifier: "short"))
        let session = TrainingSession(startedAt: video.recordedStartAt, endedAt: video.recordedStartAt.addingTimeInterval(1),
            events: [ShotMarkerEvent(markedAt: video.recordedStartAt.addingTimeInterval(0.2))])
        let task = try HighlightTaskPlanner.makeTask(id: UUID(), session: session, videos: [video], settings: .default)
        let execution = try HighlightTaskPlanner.execution(for: task)
        XCTAssertEqual(execution.snapshot.segments[0].start, 0)
        XCTAssertEqual(execution.snapshot.segments[0].duration, 0.55)
    }

    func testTiedMarkersUseSnapshotSourceOrderInsteadOfRandomLocalUUIDOrder() throws {
        let date = Date(timeIntervalSince1970: 110)
        let input = TrainingSession(startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 160), events: [
            ShotMarkerEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, markedAt: date),
            ShotMarkerEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, markedAt: date),
        ])
        let task = try HighlightTaskPlanner.makeTask(id: UUID(), session: input, videos: [HighlightTaskTestFixture.video()], settings: .default)
        XCTAssertEqual(task.reviewItems[0].markerIDs, task.trainingSnapshot.markers.map(\.id))
        XCTAssertEqual(task.trainingSnapshot.markers.map(\.sourceOrder), [0, 1])
        let draft = try HighlightTaskPlanner.reviewDraft(for: task)
        XCTAssertEqual(draft.items[0].markerReferences.map(\.originalMatchedNumber), [1, 2])
    }

    func testSameInputsCreateIndependentTaskAndMarkerIdentitiesWithSameRanges() throws {
        let first = try HighlightTaskTestFixture.task()
        let second = try HighlightTaskTestFixture.task()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(Set(first.trainingSnapshot.markers.map(\.id)).isDisjoint(with: second.trainingSnapshot.markers.map(\.id)))
        XCTAssertEqual(first.reviewItems.map(\.start), [1, 31])
        XCTAssertEqual(first.reviewItems.map(\.duration), [15, 13])
        XCTAssertEqual(second.reviewItems.map(\.start), [1, 31])
    }

    func testDefaultChangePreservesConfirmedRangeAndExclusionButRefreshesBaseline() throws {
        var task = try HighlightTaskTestFixture.task()
        task.reviewItems[0].confirmationState = .confirmed
        task.reviewItems[0].start = 7
        task.reviewItems[0].duration = 4
        task.reviewItems[0].isIncluded = false
        let result = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos,
            settings: ClipSettings(secondsBeforeMarker: 3, secondsAfterMarker: 2))
        XCTAssertEqual(result.items.map(\.start), [7, 37])
        XCTAssertEqual(result.items.map(\.defaultStart), [7, 37])
        XCTAssertEqual(result.items[0].defaultDuration, 7)
        XCTAssertEqual(result.items[0].duration, 4)
        XCTAssertFalse(result.items[0].isIncluded)
        XCTAssertEqual(result.items[0].confirmationState, .confirmed)
        XCTAssertEqual(result.resetConfirmationCount, 0)
    }

    func testVideoReorderResetsOnlyConfirmedMarkersWhoseMappingChanged() throws {
        var task = try HighlightTaskTestFixture.task()
        task.reviewItems[0].confirmationState = .confirmed
        let overlap = HighlightTaskVideo(id: UUID(), sourceIdentity: .photoLibraryAsset("overlap"),
            recordedStartAt: Date(timeIntervalSince1970: 100), duration: 20,
            source: .photoLibraryAsset(localIdentifier: "overlap"))
        let appended = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos + [overlap], settings: task.clipSettings)
        XCTAssertEqual(appended.resetConfirmationCount, 0)
        XCTAssertEqual(appended.items[0].id, task.reviewItems[0].id)
        let reordered = try HighlightTaskPlanner.reconcile(task: task, videos: [overlap] + task.videos, settings: task.clipSettings)
        XCTAssertEqual(reordered.resetConfirmationCount, 1)
        XCTAssertEqual(reordered.items[0].videoID, overlap.id)
        XCTAssertEqual(reordered.items[0].confirmationState, .defaultValue)
        XCTAssertEqual(Set(reordered.items.flatMap(\.markerIDs)).count, 3)
    }

    func testStyleOnlyDoesNotReplanAndResetAllDiscardsConfirmations() throws {
        var task = try HighlightTaskTestFixture.task()
        task.reviewItems[0].confirmationState = .confirmed
        task.reviewItems[0].isIncluded = false
        var settings = task.clipSettings
        settings.markerLabelStyle.textOpacity = 0.2
        let style = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos, settings: settings)
        XCTAssertEqual(style.items, task.reviewItems)
        let reset = try HighlightTaskPlanner.reconcile(task: task, videos: task.videos, settings: settings, resetAll: true)
        XCTAssertTrue(reset.items.allSatisfy { $0.isIncluded && $0.confirmationState == .defaultValue })
        XCTAssertEqual(reset.items.map(\.start), [1, 31])
    }
}

private extension HighlightTaskVideo {
    var recordedEndAtForTest: Date { recordedStartAt.addingTimeInterval(duration) }
}

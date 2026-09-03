@testable import ShotMarker
import XCTest

final class HighlightClipReviewRestorationTests: XCTestCase {
    func testNoRecordMatchesCurrentDefaultDraftExactly() {
        let fixture = makeFixture()

        let restored = HighlightClipReviewPlanner.restoreDraft(
            for: fixture.session,
            videos: fixture.videos,
            clipSettings: fixture.settings,
            persistedRecord: nil,
        )

        XCTAssertEqual(
            restored.draft,
            HighlightClipReviewPlanner.makeDraft(
                for: fixture.session,
                videos: fixture.videos,
                clipSettings: fixture.settings,
            ),
        )
        XCTAssertTrue(restored.draft.items.allSatisfy {
            $0.confirmationState == .defaultValue
        })
        XCTAssertEqual(restored.discardedConfirmationCount, 0)
    }

    func testConfirmedItemRestoresExactRangeBaselineMarkersAndIncludedState() {
        let fixture = makeFixture()
        let confirmation = makeConfirmation(
            fixture: fixture,
            markerIDs: [fixture.markers[1].id],
            defaultStart: 8,
            defaultDuration: 13,
            start: 10.2,
            duration: 2.4,
            isIncluded: true,
        )

        let restored = restore(fixture, confirmations: [confirmation])
        let item = restored.draft.items.first {
            $0.markerReferences.map(\.id) == confirmation.markerIDs
        }!

        XCTAssertEqual(item.defaultRange, HighlightClipRange(start: 8, duration: 13))
        XCTAssertEqual(item.range, HighlightClipRange(start: 10.2, duration: 2.4))
        XCTAssertTrue(item.isIncluded)
        XCTAssertEqual(item.confirmationState, .confirmed)
    }

    func testConfirmedExcludedMarkersNeverReturnAsDefaultItems() {
        let fixture = makeFixture()
        let markerIDs = [fixture.markers[1].id, fixture.markers[2].id]
        let confirmation = makeConfirmation(
            fixture: fixture,
            markerIDs: markerIDs,
            start: 10,
            duration: 4,
            isIncluded: false,
        )

        let restored = restore(fixture, confirmations: [confirmation])
        let occurrences = restored.draft.items
            .flatMap(\.markerReferences)
            .filter { markerIDs.contains($0.id) }

        XCTAssertEqual(occurrences.map(\.id), markerIDs)
        XCTAssertFalse(restored.draft.items.first {
            $0.markerReferences.map(\.id) == markerIDs
        }!.isIncluded)
    }

    func testChangingGlobalDurationsReplansOnlyDefaultItems() {
        let fixture = makeFixture()
        let confirmation = makeConfirmation(
            fixture: fixture,
            markerIDs: [fixture.markers[1].id],
            defaultStart: 8,
            defaultDuration: 13,
            start: 10,
            duration: 2,
            isIncluded: true,
        )
        let original = restore(fixture, confirmations: [confirmation])
        var changedSettings = fixture.settings
        changedSettings.secondsBeforeMarker = 2
        changedSettings.secondsAfterMarker = 2

        let changed = HighlightClipReviewPlanner.restoreDraft(
            for: fixture.session,
            videos: fixture.videos,
            clipSettings: changedSettings,
            persistedRecord: makePersistedRecord(fixture, confirmations: [confirmation]),
        )

        let originalConfirmed = original.draft.items.first { $0.confirmationState == .confirmed }
        let changedConfirmed = changed.draft.items.first { $0.confirmationState == .confirmed }
        XCTAssertEqual(changedConfirmed, originalConfirmed)
        XCTAssertNotEqual(
            changed.draft.items.filter { $0.confirmationState == .defaultValue }.map(\.range),
            original.draft.items.filter { $0.confirmationState == .defaultValue }.map(\.range),
        )
    }

    func testDefaultItemsDoNotMergeAcrossConfirmedMarkerAndOrderStaysOriginal() {
        let fixture = makeCloseMarkerFixture()
        let middle = makeConfirmation(
            fixture: fixture,
            markerIDs: [fixture.markers[1].id],
            start: 10,
            duration: 1,
            isIncluded: true,
        )

        let items = restore(fixture, confirmations: [middle]).draft.items

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map { $0.markerReferences.map(\.id) }, [
            [fixture.markers[0].id],
            [fixture.markers[1].id],
            [fixture.markers[2].id],
        ])
        XCTAssertEqual(items.map(\.confirmationState), [
            .defaultValue, .confirmed, .defaultValue,
        ])
    }

    func testOneInvalidConfirmationFallsBackOnlyItsMarkersAndReportsCount() {
        let fixture = makeFixture()
        let valid = makeConfirmation(
            fixture: fixture,
            markerIDs: [fixture.markers[0].id],
            start: 2,
            duration: 2,
            isIncluded: true,
        )
        let invalid = makeConfirmation(
            fixture: fixture,
            markerIDs: [fixture.markers[2].id],
            start: -1,
            duration: 0,
            isIncluded: true,
        )

        let restored = restore(fixture, confirmations: [valid, invalid])

        XCTAssertEqual(restored.discardedConfirmationCount, 1)
        XCTAssertEqual(
            restored.draft.items.first {
                $0.markerReferences.contains { $0.id == valid.markerIDs[0] }
            }?.confirmationState,
            .confirmed,
        )
        XCTAssertEqual(
            restored.draft.items.first {
                $0.markerReferences.contains { $0.id == invalid.markerIDs[0] }
            }?.confirmationState,
            .defaultValue,
        )
    }

    func testRestoredDraftUsesExistingSummaryAndSnapshotPipeline() throws {
        let fixture = makeFixture()
        let excluded = makeConfirmation(
            fixture: fixture,
            markerIDs: [fixture.markers[1].id],
            start: 10,
            duration: 2,
            isIncluded: false,
        )
        let draft = restore(fixture, confirmations: [excluded]).draft

        let summary = try HighlightClipReviewPlanner.makeSummary(
            items: draft.items,
            videos: fixture.videos,
        )
        let segments = try HighlightClipReviewPlanner.validateConfirmedSegments(
            summary.finalSegments,
            videos: fixture.videos,
            validMarkerIDs: Set(draft.items.flatMap(\.markerReferences).map(\.id)),
        )

        XCTAssertEqual(summary.excludedMarkerCount, 1)
        XCTAssertFalse(segments.flatMap(\.markerIDs).contains(excluded.markerIDs[0]))
    }

    func testEveryInvalidConfirmationFallsBackWithoutDiscardingLegalDefaults() {
        let fixture = makeFixture()
        let base = makeConfirmation(
            fixture: fixture,
            markerIDs: [fixture.markers[0].id],
            start: 2,
            duration: 2,
            isIncluded: true,
        )
        let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000009999")!
        let otherVideoIdentity = HighlightClipReviewVideoIdentity(
            source: .photoLibraryAsset("other"),
            recordedStartAtMilliseconds: 0,
            durationTicks: 600,
        )
        let invalidItems = [
            altered(base, markerIDs: [missingID]),
            altered(base, markerIDs: [fixture.markers[0].id, fixture.markers[0].id]),
            altered(base, markerIDs: [fixture.markers[1].id, fixture.markers[0].id]),
            altered(base, markerIDs: [fixture.markers[0].id, fixture.markers[2].id]),
            altered(base, markerIDs: [fixture.markers[2].id, fixture.markers[3].id]),
            altered(base, videoIdentity: otherVideoIdentity),
            altered(base, start: fixture.videos[0].duration, duration: 2),
            altered(base, defaultStart: -1, defaultDuration: 0),
            altered(base, start: 2.05, duration: 1.95),
        ]

        for invalid in invalidItems {
            let restored = restore(fixture, confirmations: [invalid])
            XCTAssertEqual(restored.discardedConfirmationCount, 1)
            XCTAssertTrue(restored.draft.items.allSatisfy {
                $0.confirmationState == .defaultValue
            })
            XCTAssertEqual(
                Set(restored.draft.items.flatMap(\.markerReferences).map(\.id)),
                Set(
                    HighlightClipReviewPlanner.makeDraft(
                        for: fixture.session,
                        videos: fixture.videos,
                        clipSettings: fixture.settings,
                    )
                    .items
                    .flatMap(\.markerReferences)
                    .map(\.id),
                ),
            )
        }
    }
}

private func altered(
    _ value: PersistedHighlightClipConfirmation,
    videoIdentity: HighlightClipReviewVideoIdentity? = nil,
    markerIDs: [UUID]? = nil,
    defaultStart: TimeInterval? = nil,
    defaultDuration: TimeInterval? = nil,
    start: TimeInterval? = nil,
    duration: TimeInterval? = nil,
) -> PersistedHighlightClipConfirmation {
    PersistedHighlightClipConfirmation(
        videoIdentity: videoIdentity ?? value.videoIdentity,
        markerIDs: markerIDs ?? value.markerIDs,
        defaultStart: defaultStart ?? value.defaultStart,
        defaultDuration: defaultDuration ?? value.defaultDuration,
        start: start ?? value.start,
        duration: duration ?? value.duration,
        isIncluded: value.isIncluded,
        confirmedAt: value.confirmedAt,
    )
}

private struct RestorationFixture {
    let session: TrainingSession
    let videos: [SelectedTrainingVideo]
    let settings: ClipSettings

    var markers: [ShotMarkerEvent] { session.events }
}

private func makeFixture() -> RestorationFixture {
    let firstStart = Date(timeIntervalSince1970: 100)
    let secondStart = Date(timeIntervalSince1970: 200)
    let markers = [
        makeRestorationMarker(index: 1, at: 110),
        makeRestorationMarker(index: 2, at: 130),
        makeRestorationMarker(index: 3, at: 150),
        makeRestorationMarker(index: 4, at: 210),
    ]
    return RestorationFixture(
        session: TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000400")!,
            startedAt: firstStart,
            endedAt: secondStart.addingTimeInterval(80),
            events: markers,
        ),
        videos: [
            SelectedTrainingVideo(
                id: "runtime-a",
                recordedStartAt: firstStart,
                duration: 80,
                reviewSourceIdentity: .photoLibraryAsset("asset-a"),
            ),
            SelectedTrainingVideo(
                id: "runtime-b",
                recordedStartAt: secondStart,
                duration: 80,
                reviewSourceIdentity: .photoLibraryAsset("asset-b"),
            ),
        ],
        settings: .default,
    )
}

private func makeCloseMarkerFixture() -> RestorationFixture {
    let start = Date(timeIntervalSince1970: 100)
    return RestorationFixture(
        session: TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            events: [
                makeRestorationMarker(index: 11, at: 110),
                makeRestorationMarker(index: 12, at: 111),
                makeRestorationMarker(index: 13, at: 112),
            ],
        ),
        videos: [
            SelectedTrainingVideo(
                id: "runtime-close",
                recordedStartAt: start,
                duration: 60,
                reviewSourceIdentity: .photoLibraryAsset("asset-close"),
            ),
        ],
        settings: .default,
    )
}

private func makeRestorationMarker(
    index: Int,
    at timestamp: TimeInterval,
) -> ShotMarkerEvent {
    ShotMarkerEvent(
        id: UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                40_000 + index,
            ),
        )!,
        markedAt: Date(timeIntervalSince1970: timestamp),
    )
}

private func makeConfirmation(
    fixture: RestorationFixture,
    markerIDs: [UUID],
    defaultStart: TimeInterval = 1,
    defaultDuration: TimeInterval = 2,
    start: TimeInterval,
    duration: TimeInterval,
    isIncluded: Bool,
) -> PersistedHighlightClipConfirmation {
    let markerDates = markerIDs.compactMap { markerID in
        fixture.markers.first(where: { $0.id == markerID })?.markedAt
    }
    let video = fixture.videos.first { video in
        markerDates.allSatisfy {
            video.recordedStartAt <= $0 && $0 <= video.recordedEndAt
        }
    }!
    return PersistedHighlightClipConfirmation(
        videoIdentity: try! HighlightClipReviewIdentityBuilder.videoIdentity(for: video),
        markerIDs: markerIDs,
        defaultStart: defaultStart,
        defaultDuration: defaultDuration,
        start: start,
        duration: duration,
        isIncluded: isIncluded,
        confirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
    )
}

private func makePersistedRecord(
    _ fixture: RestorationFixture,
    confirmations: [PersistedHighlightClipConfirmation],
) -> PersistedHighlightClipReview {
    let key = try! HighlightClipReviewIdentityBuilder.combinationKey(
        for: fixture.session,
        videos: fixture.videos,
    )
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return PersistedHighlightClipReview(
        combinationDigest: key.digest,
        combination: key.combination,
        confirmedItems: confirmations,
        createdAt: now,
        updatedAt: now,
    )
}

private func restore(
    _ fixture: RestorationFixture,
    confirmations: [PersistedHighlightClipConfirmation],
) -> HighlightClipReviewRestorationResult {
    HighlightClipReviewPlanner.restoreDraft(
        for: fixture.session,
        videos: fixture.videos,
        clipSettings: fixture.settings,
        persistedRecord: makePersistedRecord(fixture, confirmations: confirmations),
    )
}

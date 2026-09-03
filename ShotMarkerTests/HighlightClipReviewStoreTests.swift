@testable import ShotMarker
import XCTest

final class HighlightClipReviewStoreTests: XCTestCase {
    func testMissingFileLoadsAsEmptyVersionOneStore() async throws {
        let fixture = makeFixture()
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

        let result = try await store.loadRecord(for: fixture.key)

        XCTAssertNil(result.record)
        XCTAssertNil(result.notice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testDigestCollisionDoesNotBypassCompleteStructureComparison() async throws {
        let fixture = makeFixture()
        let firstKey = fixture.key
        let different = HighlightClipReviewCombinationKey(
            digest: firstKey.digest,
            combination: makeDifferentCombination(from: firstKey.combination),
        )
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        try await store.upsert(fixture.confirmation, for: firstKey, now: fixture.now)

        let loaded = try await store.loadRecord(for: different)
        XCTAssertNil(loaded.record)
    }

    func testCorruptRootMovesRecoveryCopyAndCreatesEmptyVersionOneDocument() async throws {
        let fixture = makeFixture()
        try Data("{not-json".utf8).write(to: fixture.fileURL)
        let store = FileHighlightClipReviewStore(
            fileURL: fixture.fileURL,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
        )

        let result = try await store.loadRecord(for: fixture.key)
        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil,
        )
        let document = try JSONDecoder().decode(
            HighlightClipReviewStoreDocument.self,
            from: Data(contentsOf: fixture.fileURL),
        )

        XCTAssertEqual(result.notice, .corruptDocumentRecovered)
        XCTAssertEqual(document, .empty)
        XCTAssertEqual(
            files.filter { $0.lastPathComponent.hasPrefix("highlight-clip-reviews.corrupt-") }.count,
            1,
        )
    }

    func testHigherSchemaLoadsWithoutRecordAndCannotBeOverwritten() async throws {
        let fixture = makeFixture()
        let futureBytes = Data(#"{"schemaVersion":2,"records":[{"future":true}]}"#.utf8)
        try futureBytes.write(to: fixture.fileURL)
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

        let result = try await store.loadRecord(for: fixture.key)
        XCTAssertNil(result.record)
        XCTAssertEqual(result.notice, .unsupportedSchemaVersion(2))
        await XCTAssertThrowsErrorAsync(
            try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now),
        ) {
            XCTAssertEqual($0 as? HighlightClipReviewStoreError, .unsupportedSchemaVersion(2))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), futureBytes)
    }

    func testUpsertRoundTripsAcrossStoreInstances() async throws {
        let fixture = makeFixture()
        try await FileHighlightClipReviewStore(fileURL: fixture.fileURL)
            .upsert(fixture.confirmation, for: fixture.key, now: fixture.now)

        let loaded = try await FileHighlightClipReviewStore(fileURL: fixture.fileURL)
            .loadRecord(for: fixture.key)
        let bytes = try Data(contentsOf: fixture.fileURL)
        let document = try JSONDecoder().decode(HighlightClipReviewStoreDocument.self, from: bytes)
        let encodedText = String(decoding: bytes, as: UTF8.self)

        XCTAssertEqual(loaded.record?.confirmedItems, [fixture.confirmation])
        XCTAssertEqual(loaded.record?.combination, fixture.key.combination)
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.records.count, 1)
        for forbiddenKey in [
            "thumbnail", "filmstrip", "player", "temporaryURL", "errorMessage", "displayNumber",
        ] {
            XCTAssertFalse(encodedText.contains(forbiddenKey))
        }
    }

    func testSecondConfirmationReplacesIdentityAndPreservesOriginalDefaultBaseline() async throws {
        let fixture = makeFixture()
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
        let replacement = fixture.confirmation.replacing(
            defaultStart: 5,
            defaultDuration: 3,
            start: 12,
            duration: 3,
            isIncluded: false,
            confirmedAt: fixture.now.addingTimeInterval(10),
        )

        try await store.upsert(replacement, for: fixture.key, now: replacement.confirmedAt)
        let record = try await store.loadRecord(for: fixture.key).record!
        let items = record.confirmedItems

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(record.createdAt, fixture.now)
        XCTAssertEqual(record.updatedAt, replacement.confirmedAt)
        XCTAssertEqual(items[0].defaultStart, fixture.confirmation.defaultStart)
        XCTAssertEqual(items[0].defaultDuration, fixture.confirmation.defaultDuration)
        XCTAssertEqual(items[0].start, 12)
        XCTAssertEqual(items[0].duration, 3)
        XCTAssertFalse(items[0].isIncluded)
    }

    func testAtomicWriterFailureLeavesPreviousBytesAndValueUntouched() async throws {
        let fixture = makeFixture()
        let working = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        try await working.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
        let oldBytes = try Data(contentsOf: fixture.fileURL)
        let failing = FileHighlightClipReviewStore(
            fileURL: fixture.fileURL,
            atomicWrite: { _, _ in throw TestError.writeFailed },
        )

        await XCTAssertThrowsErrorAsync(
            try await failing.upsert(
                fixture.confirmation.replacing(start: 20),
                for: fixture.key,
                now: fixture.now.addingTimeInterval(1),
            ),
        )

        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), oldBytes)
        let reloadedStart = try await working.loadRecord(for: fixture.key)
            .record?.confirmedItems[0].start
        XCTAssertEqual(reloadedStart, fixture.confirmation.start)
    }

    func testConcurrentUpsertsRetainEverySuccessfulDistinctItem() async throws {
        let fixture = makeFixture()
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        let confirmations = (1...8).map { fixture.confirmation.withMarker(index: $0) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for confirmation in confirmations {
                group.addTask {
                    try await store.upsert(confirmation, for: fixture.key, now: confirmation.confirmedAt)
                }
            }
            try await group.waitForAll()
        }

        let loaded = try await store.loadRecord(for: fixture.key).record!.confirmedItems
        XCTAssertEqual(Set(loaded.map(\.identity)), Set(confirmations.map(\.identity)))
    }

    func testOverlappingDifferentConfirmationIdentityIsRejected() async throws {
        let fixture = makeFixture()
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
        let overlap = fixture.confirmation.withMarkerIDs([
            fixture.confirmation.markerIDs[0],
            storeMarkerID(2),
        ])

        await XCTAssertThrowsErrorAsync(
            try await store.upsert(overlap, for: fixture.key, now: fixture.now),
        ) {
            XCTAssertEqual($0 as? HighlightClipReviewStoreError, .duplicateMarkerAssignment)
        }
    }

    func testDeleteTrainingRemovesAllItsCombinationsOnly() async throws {
        let fixture = makeFixture()
        let other = makeFixture(trainingID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!)
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
        try await store.upsert(other.confirmation, for: other.key, now: other.now)

        try await store.deleteRecords(forTrainingSessionID: fixture.key.combination.training.id)

        let deleted = try await store.loadRecord(for: fixture.key)
        let preserved = try await store.loadRecord(for: other.key)
        XCTAssertNil(deleted.record)
        XCTAssertNotNil(preserved.record)
    }

    func testReconcileRemovesMissingAndChangedTrainingIdentities() async throws {
        let fixture = makeFixture()
        let current = makeFixture(trainingID: fixture.key.combination.training.id, markerOffset: 1)
        let retained = makeFixture(trainingID: UUID(uuidString: "00000000-0000-0000-0000-000000000088")!)
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)
        try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
        try await store.upsert(retained.confirmation, for: retained.key, now: retained.now)

        try await store.reconcile(validTrainingIdentities: [
            current.key.combination.training,
            retained.key.combination.training,
        ])

        let removed = try await store.loadRecord(for: fixture.key)
        let preserved = try await store.loadRecord(for: retained.key)
        XCTAssertNil(removed.record)
        XCTAssertNotNil(preserved.record)
    }

    func testDifferentCombinationsForSameTrainingCoexist() async throws {
        let fixture = makeFixture()
        let otherOrder = fixture.reversingVideoOrder()
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

        try await store.upsert(fixture.confirmation, for: fixture.key, now: fixture.now)
        try await store.upsert(otherOrder.confirmation, for: otherOrder.key, now: otherOrder.now)

        let originalLoaded = try await store.loadRecord(for: fixture.key)
        let reorderedLoaded = try await store.loadRecord(for: otherOrder.key)
        XCTAssertEqual(originalLoaded.record?.confirmedItems, [fixture.confirmation])
        XCTAssertEqual(reorderedLoaded.record?.confirmedItems, [otherOrder.confirmation])
    }

    func testExcludedConfirmationRoundTripsRangeAndState() async throws {
        let fixture = makeFixture()
        let excluded = fixture.confirmation.replacing(
            start: 4.2,
            duration: 3.1,
            isIncluded: false,
        )
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

        try await store.upsert(excluded, for: fixture.key, now: fixture.now)
        let loaded = try await store.loadRecord(for: fixture.key).record!.confirmedItems[0]

        XCTAssertEqual(loaded.start, 4.2)
        XCTAssertEqual(loaded.duration, 3.1)
        XCTAssertFalse(loaded.isIncluded)
    }

    func testLoadingDefaultsWithoutUpsertDoesNotCreateARecordOrFile() async throws {
        let fixture = makeFixture()
        let store = FileHighlightClipReviewStore(fileURL: fixture.fileURL)

        _ = try await store.loadRecord(for: fixture.key)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }
}

private nonisolated final class StoreFixture: @unchecked Sendable {
    let directoryURL: URL
    let fileURL: URL
    let key: HighlightClipReviewCombinationKey
    let confirmation: PersistedHighlightClipConfirmation
    let now: Date
    private let ownsDirectory: Bool

    init(
        directoryURL: URL,
        key: HighlightClipReviewCombinationKey,
        confirmation: PersistedHighlightClipConfirmation,
        now: Date,
        ownsDirectory: Bool = true,
    ) {
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent("highlight-clip-reviews.json")
        self.key = key
        self.confirmation = confirmation
        self.now = now
        self.ownsDirectory = ownsDirectory
    }

    deinit {
        if ownsDirectory {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func reversingVideoOrder() -> StoreFixture {
        let reversed = HighlightClipReviewCombination(
            training: key.combination.training,
            videos: Array(key.combination.videos.reversed()),
        )
        return StoreFixture(
            directoryURL: directoryURL,
            key: HighlightClipReviewCombinationKey(
                digest: "\(key.digest)-reversed",
                combination: reversed,
            ),
            confirmation: confirmation,
            now: now.addingTimeInterval(1),
            ownsDirectory: false,
        )
    }
}

private nonisolated func makeFixture(
    trainingID: UUID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000100",
    )!,
    markerOffset: Int = 0,
) -> StoreFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
    )
    let markers = (1...8).map { index in
        HighlightClipReviewMarkerIdentity(
            id: storeMarkerID(markerOffset + index),
            markedAtMilliseconds: Int64(110_000 + ((markerOffset + index) * 1_000)),
        )
    }
    let training = HighlightClipReviewTrainingIdentity(
        id: trainingID,
        startedAtMilliseconds: 100_000,
        endedAtMilliseconds: 200_000,
        markers: markers,
    )
    let videos = [
        HighlightClipReviewVideoIdentity(
            source: .photoLibraryAsset("asset-a"),
            recordedStartAtMilliseconds: 100_000,
            durationTicks: 60 * 600,
        ),
        HighlightClipReviewVideoIdentity(
            source: .photoLibraryAsset("asset-b"),
            recordedStartAtMilliseconds: 200_000,
            durationTicks: 60 * 600,
        ),
    ]
    let combination = HighlightClipReviewCombination(
        training: training,
        videos: videos,
    )
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return StoreFixture(
        directoryURL: directory,
        key: HighlightClipReviewCombinationKey(
            digest: "digest-\(trainingID.uuidString)-\(markerOffset)",
            combination: combination,
        ),
        confirmation: PersistedHighlightClipConfirmation(
            videoIdentity: videos[0],
            markerIDs: [markers[0].id],
            defaultStart: 1,
            defaultDuration: 2,
            start: 1,
            duration: 2,
            isIncluded: true,
            confirmedAt: now,
        ),
        now: now,
    )
}

private nonisolated func makeDifferentCombination(
    from value: HighlightClipReviewCombination,
) -> HighlightClipReviewCombination {
    HighlightClipReviewCombination(
        training: HighlightClipReviewTrainingIdentity(
            id: value.training.id,
            startedAtMilliseconds: value.training.startedAtMilliseconds + 1,
            endedAtMilliseconds: value.training.endedAtMilliseconds,
            markers: value.training.markers,
        ),
        videos: value.videos,
    )
}

private nonisolated func storeMarkerID(_ index: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "00000000-0000-0000-0000-%012d",
            90_000 + index,
        ),
    )!
}

private nonisolated extension PersistedHighlightClipConfirmation {
    func replacing(
        defaultStart: TimeInterval? = nil,
        defaultDuration: TimeInterval? = nil,
        start: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        isIncluded: Bool? = nil,
        confirmedAt: Date? = nil,
    ) -> Self {
        Self(
            videoIdentity: videoIdentity,
            markerIDs: markerIDs,
            defaultStart: defaultStart ?? self.defaultStart,
            defaultDuration: defaultDuration ?? self.defaultDuration,
            start: start ?? self.start,
            duration: duration ?? self.duration,
            isIncluded: isIncluded ?? self.isIncluded,
            confirmedAt: confirmedAt ?? self.confirmedAt,
        )
    }

    func withMarker(index: Int) -> Self {
        withMarkerIDs([storeMarkerID(index)])
            .replacing(confirmedAt: confirmedAt.addingTimeInterval(Double(index)))
    }

    func withMarkerIDs(_ markerIDs: [UUID]) -> Self {
        Self(
            videoIdentity: videoIdentity,
            markerIDs: markerIDs,
            defaultStart: defaultStart,
            defaultDuration: defaultDuration,
            start: start,
            duration: duration,
            isIncluded: isIncluded,
            confirmedAt: confirmedAt,
        )
    }
}

private nonisolated func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw")
    } catch {
        errorHandler(error)
    }
}

private nonisolated enum TestError: Error {
    case writeFailed
}

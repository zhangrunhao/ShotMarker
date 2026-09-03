@testable import ShotMarker
import XCTest

final class TrainingSessionImporterTests: XCTestCase {
    func testReplacingChangedWatchSessionDeletesItsReviewRecordsAfterTrainingSave() async throws {
        let original = makeSession(markerOffset: 0)
        let changed = makePayload(id: original.id, markerOffset: 1)
        let trainingStore = InMemoryTrainingSessionStore(sessions: [original])
        let reviewStore = InMemoryHighlightClipReviewStore()
        let importer = TrainingSessionImporter(
            store: trainingStore,
            reviewStore: reviewStore,
        )

        try await importer.import(changed)
        let deletedIDs = await reviewStore.deletedTrainingSessionIDs

        XCTAssertEqual(
            try trainingStore.loadTrainingSessions().first?.events.first?.id,
            changed.events.first?.id,
        )
        XCTAssertEqual(deletedIDs, [original.id])
    }

    func testImportingByteEquivalentTrainingDoesNotDeleteConfirmations() async throws {
        let session = makeSession()
        let reviewStore = InMemoryHighlightClipReviewStore()
        let importer = TrainingSessionImporter(
            store: InMemoryTrainingSessionStore(sessions: [session]),
            reviewStore: reviewStore,
        )

        try await importer.import(payload(from: session))
        let deletedIDs = await reviewStore.deletedTrainingSessionIDs

        XCTAssertTrue(deletedIDs.isEmpty)
    }

    func testCleanupFailureDoesNotFailSuccessfulTrainingImport() async throws {
        let original = makeSession(markerOffset: 0)
        let reviewStore = InMemoryHighlightClipReviewStore(deleteError: TestError.cleanupFailed)
        let importer = TrainingSessionImporter(
            store: InMemoryTrainingSessionStore(sessions: [original]),
            reviewStore: reviewStore,
        )

        try await importer.import(makePayload(id: original.id, markerOffset: 1))
    }

    func testImportPayloadSavesTrainingSessionInStore() async throws {
        let store = InMemoryTrainingSessionStore(sessions: [])
        let importer = TrainingSessionImporter(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
        )
        let payload = try makePayload()

        try await importer.import(payload)

        XCTAssertEqual(try store.loadTrainingSessions(), [
            try makeTrainingSession(from: payload),
        ])
    }

    func testImportingSamePayloadTwiceKeepsSingleTrainingSession() async throws {
        let store = InMemoryTrainingSessionStore(sessions: [])
        let importer = TrainingSessionImporter(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
        )
        let payload = try makePayload()

        try await importer.import(payload)
        try await importer.import(payload)

        XCTAssertEqual(try store.loadTrainingSessions(), [
            try makeTrainingSession(from: payload),
        ])
    }

    func testImportingExistingTrainingSessionIdReplacesStoredSession() async throws {
        let payload = try makePayload()
        let unrelatedSession = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000704")),
            startedAt: Date(timeIntervalSince1970: 8000),
            endedAt: Date(timeIntervalSince1970: 8600),
            events: [],
        )
        let staleSession = TrainingSession(
            id: payload.id,
            startedAt: Date(timeIntervalSince1970: 9000),
            endedAt: Date(timeIntervalSince1970: 9600),
            events: [],
        )
        let store = InMemoryTrainingSessionStore(sessions: [unrelatedSession, staleSession])
        let importer = TrainingSessionImporter(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        try await importer.import(payload)

        XCTAssertEqual(try store.loadTrainingSessions(), [
            unrelatedSession,
            try makeTrainingSession(from: payload),
        ])
    }

    private func makePayload() throws -> TrainingSessionSyncPayload {
        TrainingSessionSyncPayload(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000701")),
            startedAt: Date(timeIntervalSince1970: 10000),
            endedAt: Date(timeIntervalSince1970: 10600),
            events: [
                ShotMarkerEventSyncPayload(
                    id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000702")),
                    markedAt: Date(timeIntervalSince1970: 10120),
                ),
                ShotMarkerEventSyncPayload(
                    id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000703")),
                    markedAt: Date(timeIntervalSince1970: 10320),
                ),
            ],
        )
    }

    private func makeTrainingSession(from payload: TrainingSessionSyncPayload) throws -> TrainingSession {
        TrainingSession(
            id: payload.id,
            startedAt: payload.startedAt,
            endedAt: payload.endedAt,
            events: payload.events.map { event in
                ShotMarkerEvent(id: event.id, markedAt: event.markedAt)
            },
        )
    }

    private func makeSession(markerOffset: Int = 0) -> TrainingSession {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        return TrainingSession(
            id: id,
            startedAt: Date(timeIntervalSince1970: 10_000),
            endedAt: Date(timeIntervalSince1970: 10_600),
            events: [
                ShotMarkerEvent(
                    id: UUID(
                        uuidString: String(
                            format: "00000000-0000-0000-0000-%012d",
                            702 + markerOffset,
                        ),
                    )!,
                    markedAt: Date(timeIntervalSince1970: 10_120 + Double(markerOffset)),
                ),
            ],
        )
    }

    private func makePayload(
        id: UUID,
        markerOffset: Int,
    ) -> TrainingSessionSyncPayload {
        let session = makeSession(markerOffset: markerOffset)
        return TrainingSessionSyncPayload(
            id: id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            events: session.events.map {
                ShotMarkerEventSyncPayload(id: $0.id, markedAt: $0.markedAt)
            },
        )
    }

    private func payload(from session: TrainingSession) -> TrainingSessionSyncPayload {
        TrainingSessionSyncPayload(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            events: session.events.map {
                ShotMarkerEventSyncPayload(id: $0.id, markedAt: $0.markedAt)
            },
        )
    }
}

private enum TestError: Error {
    case cleanupFailed
}

@testable import ShotMarker
import XCTest

final class TrainingSessionImporterTests: XCTestCase {
    func testImportPayloadSavesTrainingSessionInStore() throws {
        let store = InMemoryTrainingSessionStore(sessions: [])
        let importer = TrainingSessionImporter(store: store)
        let payload = try makePayload()

        try importer.import(payload)

        XCTAssertEqual(try store.loadTrainingSessions(), [
            try makeTrainingSession(from: payload),
        ])
    }

    func testImportingSamePayloadTwiceKeepsSingleTrainingSession() throws {
        let store = InMemoryTrainingSessionStore(sessions: [])
        let importer = TrainingSessionImporter(store: store)
        let payload = try makePayload()

        try importer.import(payload)
        try importer.import(payload)

        XCTAssertEqual(try store.loadTrainingSessions(), [
            try makeTrainingSession(from: payload),
        ])
    }

    func testImportingExistingTrainingSessionIdReplacesStoredSession() throws {
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
        let importer = TrainingSessionImporter(store: store)

        try importer.import(payload)

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
}

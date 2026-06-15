@testable import ShotMarker
import XCTest

final class TrainingSessionJSONTransferServiceTests: XCTestCase {
    func testImportTrainingSessionsInsertsNewSessionsAndReplacesMatchingIDs() throws {
        let existingSession = try makeSession(
            id: "00000000-0000-0000-0000-000000001001",
            startedAt: 1000,
        )
        let staleSession = try makeSession(
            id: "00000000-0000-0000-0000-000000001002",
            startedAt: 2000,
        )
        let replacementSession = try makeSession(
            id: "00000000-0000-0000-0000-000000001002",
            startedAt: 3000,
        )
        let newSession = try makeSession(
            id: "00000000-0000-0000-0000-000000001003",
            startedAt: 4000,
        )
        let store = InMemoryTrainingSessionStore(sessions: [existingSession, staleSession])
        let service = TrainingSessionJSONTransferService(store: store)
        let data = try JSONEncoder().encode([replacementSession, newSession])

        let result = try service.importTrainingSessions(from: data)

        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(result.replacedCount, 1)
        XCTAssertEqual(try store.loadTrainingSessions(), [
            existingSession,
            replacementSession,
            newSession,
        ])
    }

    func testImportTrainingSessionsAcceptsSingleTrainingSessionObject() throws {
        let session = try makeSession(
            id: "00000000-0000-0000-0000-000000001004",
            startedAt: 5000,
        )
        let store = InMemoryTrainingSessionStore(sessions: [])
        let service = TrainingSessionJSONTransferService(store: store)
        let data = try JSONEncoder().encode(session)

        let result = try service.importTrainingSessions(from: data)

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(result.replacedCount, 0)
        XCTAssertEqual(try store.loadTrainingSessions(), [session])
    }

    func testImportTrainingSessionsPostsChangeNotificationAfterSaving() throws {
        let notificationCenter = NotificationCenter()
        let store = InMemoryTrainingSessionStore(sessions: [])
        let service = TrainingSessionJSONTransferService(
            store: store,
            notificationCenter: notificationCenter,
        )
        let session = try makeSession(
            id: "00000000-0000-0000-0000-000000001101",
            startedAt: 1000,
        )
        let data = try JSONEncoder().encode([session])
        let notificationPosted = expectation(description: "trainingSessionsDidChange posted")
        let observer = notificationCenter.addObserver(
            forName: .trainingSessionsDidChange,
            object: nil,
            queue: nil,
        ) { _ in
            notificationPosted.fulfill()
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        _ = try service.importTrainingSessions(from: data)

        wait(for: [notificationPosted], timeout: 1)
    }

    func testExportTrainingSessionsEncodesSelectedSessionsAsJSONArray() throws {
        let firstSession = try makeSession(
            id: "00000000-0000-0000-0000-000000001201",
            startedAt: 1000,
        )
        let secondSession = try makeSession(
            id: "00000000-0000-0000-0000-000000001202",
            startedAt: 2000,
        )
        let service = TrainingSessionJSONTransferService(store: InMemoryTrainingSessionStore(sessions: []))

        let data = try service.exportData(for: [firstSession, secondSession])

        XCTAssertEqual(try JSONDecoder().decode([TrainingSession].self, from: data), [
            firstSession,
            secondSession,
        ])
    }

    func testExportTrainingSessionsRejectsEmptySelection() throws {
        let service = TrainingSessionJSONTransferService(store: InMemoryTrainingSessionStore(sessions: []))

        XCTAssertThrowsError(try service.exportData(for: [])) { error in
            XCTAssertEqual(error as? TrainingSessionJSONTransferError, .emptyExportSelection)
        }
    }

    private func makeSession(id: String, startedAt: TimeInterval) throws -> TrainingSession {
        try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: id)),
            startedAt: Date(timeIntervalSince1970: startedAt),
            endedAt: Date(timeIntervalSince1970: startedAt + 600),
            events: [
                ShotMarkerEvent(
                    id: UUID(),
                    markedAt: Date(timeIntervalSince1970: startedAt + 120),
                ),
            ],
        )
    }
}

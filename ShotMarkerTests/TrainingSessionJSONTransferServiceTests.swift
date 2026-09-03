@testable import ShotMarker
import XCTest

final class TrainingSessionJSONTransferServiceTests: XCTestCase {
    func testJSONImportDeletesOnlyReplacedChangedTrainingIdentities() async throws {
        let changedID = "00000000-0000-0000-0000-000000001301"
        let identicalID = "00000000-0000-0000-0000-000000001302"
        let insertedID = "00000000-0000-0000-0000-000000001303"
        let changedOriginal = try makeSession(id: changedID, startedAt: 1_000)
        let changedImport = try makeSession(id: changedID, startedAt: 1_100)
        let identical = try makeSession(id: identicalID, startedAt: 2_000)
        let inserted = try makeSession(id: insertedID, startedAt: 3_000)
        let reviewStore = InMemoryHighlightClipReviewStore()
        let service = TrainingSessionJSONTransferService(
            store: InMemoryTrainingSessionStore(sessions: [changedOriginal, identical]),
            reviewStore: reviewStore,
        )
        let bytes = try JSONEncoder().encode([changedImport, identical, inserted])

        let result = try await service.importTrainingSessions(from: bytes)
        let deletedIDs = await reviewStore.deletedTrainingSessionIDs

        XCTAssertEqual(result.importedCount, 3)
        XCTAssertEqual(result.replacedCount, 2)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(deletedIDs, [changedOriginal.id])
    }

    func testJSONImportCleanupFailureStillReturnsSuccessfulImportResult() async throws {
        let changedID = "00000000-0000-0000-0000-000000001311"
        let original = try makeSession(id: changedID, startedAt: 1_000)
        let changed = try makeSession(id: changedID, startedAt: 1_100)
        let service = TrainingSessionJSONTransferService(
            store: InMemoryTrainingSessionStore(sessions: [original]),
            reviewStore: InMemoryHighlightClipReviewStore(
                deleteError: TestError.cleanupFailed,
            ),
        )

        let result = try await service.importTrainingSessions(
            from: JSONEncoder().encode([changed]),
        )

        XCTAssertEqual(result.replacedCount, 1)
    }

    func testImportTrainingSessionsInsertsNewSessionsAndReplacesMatchingIDs() async throws {
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
        let service = TrainingSessionJSONTransferService(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
        )
        let data = try JSONEncoder().encode([replacementSession, newSession])

        let result = try await service.importTrainingSessions(from: data)

        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(result.replacedCount, 1)
        XCTAssertEqual(try store.loadTrainingSessions(), [
            existingSession,
            replacementSession,
            newSession,
        ])
    }

    func testImportTrainingSessionsAcceptsSingleTrainingSessionObject() async throws {
        let session = try makeSession(
            id: "00000000-0000-0000-0000-000000001004",
            startedAt: 5000,
        )
        let store = InMemoryTrainingSessionStore(sessions: [])
        let service = TrainingSessionJSONTransferService(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
        )
        let data = try JSONEncoder().encode(session)

        let result = try await service.importTrainingSessions(from: data)

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(result.replacedCount, 0)
        XCTAssertEqual(try store.loadTrainingSessions(), [session])
    }

    func testImportTrainingSessionsPostsChangeNotificationAfterSaving() async throws {
        let notificationCenter = NotificationCenter()
        let store = InMemoryTrainingSessionStore(sessions: [])
        let service = TrainingSessionJSONTransferService(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
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

        _ = try await service.importTrainingSessions(from: data)

        await fulfillment(of: [notificationPosted], timeout: 1)
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
        let service = TrainingSessionJSONTransferService(
            store: InMemoryTrainingSessionStore(sessions: []),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        let data = try service.exportData(for: [firstSession, secondSession])

        XCTAssertEqual(try JSONDecoder().decode([TrainingSession].self, from: data), [
            firstSession,
            secondSession,
        ])
    }

    func testExportTrainingSessionsRejectsEmptySelection() throws {
        let service = TrainingSessionJSONTransferService(
            store: InMemoryTrainingSessionStore(sessions: []),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

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

private enum TestError: Error {
    case cleanupFailed
}

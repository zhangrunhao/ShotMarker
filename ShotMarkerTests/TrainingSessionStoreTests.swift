@testable import ShotMarker
import XCTest

final class TrainingSessionStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testLoadReturnsEmptyArrayWhenFileDoesNotExist() throws {
        let store = TrainingSessionStore(fileURL: temporaryDirectory.appendingPathComponent("missing.json"))

        let sessions = try store.loadTrainingSessions()

        XCTAssertEqual(sessions, [])
    }

    func testShotMarkerEventEncodingDoesNotIncludeSource() throws {
        let event = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000012")),
            markedAt: Date(timeIntervalSince1970: 10120),
        )

        let jsonObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any]

        XCTAssertNil(jsonObject?["source"])
    }

    func testTrainingSessionEncodingUsesMinimalPersistedFields() throws {
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000013")),
            startedAt: Date(timeIntervalSince1970: 10000),
            endedAt: Date(timeIntervalSince1970: 10600),
            events: [],
        )

        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        let keys = Set(jsonObject.keys)

        XCTAssertEqual(keys, Set(["id", "startedAt", "endedAt", "events"]))
    }

    func testSaveAndLoadRoundTripsTrainingSessions() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("training-sessions.json")
        let store = TrainingSessionStore(fileURL: fileURL)
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010")),
            startedAt: Date(timeIntervalSince1970: 10000),
            endedAt: Date(timeIntervalSince1970: 10600),
            events: [
                ShotMarkerEvent(
                    id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011")),
                    markedAt: Date(timeIntervalSince1970: 10120),
                ),
            ],
        )

        try store.saveTrainingSessions([session])

        XCTAssertEqual(try store.loadTrainingSessions(), [session])
    }

    func testLoadWritesSeedSessionsWhenFileDoesNotExist() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("seeded-training-sessions.json")
        let store = TrainingSessionStore(fileURL: fileURL, seedSessions: TrainingSession.previewSessions)

        let sessions = try store.loadTrainingSessions()

        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions, TrainingSession.previewSessions)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try TrainingSessionStore(fileURL: fileURL).loadTrainingSessions(), TrainingSession.previewSessions)
    }
}

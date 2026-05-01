import XCTest
@testable import ShotMarker

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

    func testSaveAndLoadRoundTripsTrainingSessions() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("training-sessions.json")
        let store = TrainingSessionStore(fileURL: fileURL)
        let session = TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            trainingDate: Date(timeIntervalSince1970: 10_000),
            startedAt: Date(timeIntervalSince1970: 10_000),
            endedAt: Date(timeIntervalSince1970: 10_600),
            events: [
                ShotMarkerEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                    markedAt: Date(timeIntervalSince1970: 10_120),
                    source: .watch
                )
            ],
            syncStatus: .synced,
            highlightStatus: .notClipped
        )

        try store.saveTrainingSessions([session])

        XCTAssertEqual(try store.loadTrainingSessions(), [session])
    }
}

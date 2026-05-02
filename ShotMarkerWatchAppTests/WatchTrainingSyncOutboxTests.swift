@testable import ShotMarkerWatchApp
import XCTest

final class WatchTrainingSyncOutboxTests: XCTestCase {
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

    func testEnqueuePersistsPayloadAsPendingTransfer() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("outbox.json")
        let outbox = WatchTrainingSyncOutbox(fileURL: fileURL)
        let payload = try makePayload()

        try outbox.enqueue(payload)

        let reloadedOutbox = WatchTrainingSyncOutbox(fileURL: fileURL)
        let entries = try reloadedOutbox.loadEntries()
        XCTAssertEqual(entries, [
            WatchTrainingSyncOutboxEntry(payload: payload, status: .pendingTransfer),
        ])
    }

    private func makePayload() throws -> TrainingSessionSyncPayload {
        TrainingSessionSyncPayload(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000401")),
            startedAt: Date(timeIntervalSince1970: 10000),
            endedAt: Date(timeIntervalSince1970: 10600),
            events: [
                ShotMarkerEventSyncPayload(
                    id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000402")),
                    markedAt: Date(timeIntervalSince1970: 10120),
                ),
            ],
        )
    }
}

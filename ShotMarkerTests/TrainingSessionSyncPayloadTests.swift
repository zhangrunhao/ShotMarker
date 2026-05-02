@testable import ShotMarker
import XCTest

final class TrainingSessionSyncPayloadTests: XCTestCase {
    func testTrainingSessionSyncPayloadJSONRoundTripsAllFields() throws {
        let payload = try TrainingSessionSyncPayload(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101")),
            startedAt: Date(timeIntervalSince1970: 10000),
            endedAt: Date(timeIntervalSince1970: 10600),
            events: [
                ShotMarkerEventSyncPayload(
                    id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102")),
                    markedAt: Date(timeIntervalSince1970: 10120),
                ),
            ],
        )

        let decodedPayload = try JSONDecoder().decode(
            TrainingSessionSyncPayload.self,
            from: JSONEncoder().encode(payload),
        )

        XCTAssertEqual(decodedPayload, payload)
        XCTAssertEqual(decodedPayload.id, payload.id)
        XCTAssertEqual(decodedPayload.startedAt, payload.startedAt)
        XCTAssertEqual(decodedPayload.endedAt, payload.endedAt)
        XCTAssertEqual(decodedPayload.events.first?.id, payload.events.first?.id)
        XCTAssertEqual(decodedPayload.events.first?.markedAt, payload.events.first?.markedAt)
    }

    func testTrainingSessionSyncAckPayloadJSONRoundTripsAllFields() throws {
        let ackPayload = try TrainingSessionSyncAckPayload(
            trainingSessionId: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201")),
            importedAt: Date(timeIntervalSince1970: 11000),
        )

        let decodedPayload = try JSONDecoder().decode(
            TrainingSessionSyncAckPayload.self,
            from: JSONEncoder().encode(ackPayload),
        )

        XCTAssertEqual(decodedPayload, ackPayload)
        XCTAssertEqual(decodedPayload.trainingSessionId, ackPayload.trainingSessionId)
        XCTAssertEqual(decodedPayload.importedAt, ackPayload.importedAt)
    }
}

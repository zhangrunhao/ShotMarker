@testable import ShotMarkerWatchApp
import XCTest

final class WatchTrainingSyncServiceTests: XCTestCase {
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

    func testInitActivatesSession() {
        let session = FakeWatchConnectivitySession(activationState: .notActivated)

        _ = WatchTrainingSyncService(outbox: makeOutbox(), session: session)

        XCTAssertEqual(session.activateCallCount, 1)
    }

    func testEnqueueTransfersEncodedPayloadWhenSessionIsActivated() throws {
        let payload = try makePayload()
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(outbox: outbox, session: session)

        try service.enqueueCompletedSession(payload)

        XCTAssertEqual(session.transferredUserInfos.count, 1)
        let userInfo = try XCTUnwrap(session.transferredUserInfos.first)
        XCTAssertEqual(
            userInfo[WatchTrainingSyncService.userInfoTypeKey] as? String,
            WatchTrainingSyncService.completedSessionUserInfoType,
        )
        let payloadData = try XCTUnwrap(userInfo[WatchTrainingSyncService.userInfoPayloadKey] as? Data)
        let decodedPayload = try JSONDecoder().decode(TrainingSessionSyncPayload.self, from: payloadData)
        XCTAssertEqual(decodedPayload, payload)
        XCTAssertEqual(try outbox.loadEntries(), [
            WatchTrainingSyncOutboxEntry(payload: payload, status: .pendingTransfer),
        ])
    }

    func testEnqueueKeepsPendingOutboxEntryWhenSessionIsNotActivated() throws {
        let payload = try makePayload()
        let session = FakeWatchConnectivitySession(activationState: .notActivated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(outbox: outbox, session: session)

        try service.enqueueCompletedSession(payload)

        XCTAssertEqual(session.transferredUserInfos.count, 0)
        XCTAssertEqual(try outbox.loadEntries(), [
            WatchTrainingSyncOutboxEntry(payload: payload, status: .pendingTransfer),
        ])
    }

    func testSuccessfulSystemTransferMarksOutboxEntryAwaitingAckWithoutDeletingIt() throws {
        let payload = try makePayload()
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(outbox: outbox, session: session)
        try service.enqueueCompletedSession(payload)

        try service.handleSystemTransferFinished(trainingSessionId: payload.id, error: nil)

        XCTAssertEqual(try outbox.loadEntries(), [
            WatchTrainingSyncOutboxEntry(payload: payload, status: .awaitingAck),
        ])
    }

    private func makeOutbox() -> WatchTrainingSyncOutbox {
        WatchTrainingSyncOutbox(fileURL: temporaryDirectory.appendingPathComponent("outbox.json"))
    }

    private func makePayload() throws -> TrainingSessionSyncPayload {
        TrainingSessionSyncPayload(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000501")),
            startedAt: Date(timeIntervalSince1970: 10000),
            endedAt: Date(timeIntervalSince1970: 10600),
            events: [
                ShotMarkerEventSyncPayload(
                    id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000502")),
                    markedAt: Date(timeIntervalSince1970: 10120),
                ),
            ],
        )
    }
}

private final class FakeWatchConnectivitySession: WatchConnectivitySessionProtocol {
    var activationState: WatchConnectivitySessionActivationState
    private(set) var activateCallCount = 0
    private(set) var transferredUserInfos: [[String: Any]] = []

    init(activationState: WatchConnectivitySessionActivationState) {
        self.activationState = activationState
    }

    func activate() {
        activateCallCount += 1
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        transferredUserInfos.append(userInfo)
    }
}

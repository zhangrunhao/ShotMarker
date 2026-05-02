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

    func testInitRetriesPendingEntriesWhenSessionIsAlreadyActivated() throws {
        let payload = try makePayload()
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        try outbox.enqueue(payload)

        _ = WatchTrainingSyncService(outbox: outbox, session: session)

        XCTAssertEqual(session.transferredUserInfos.count, 1)
        XCTAssertEqual(try decodePayload(from: try XCTUnwrap(session.transferredUserInfos.first)), payload)
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
            WatchTrainingSyncOutboxEntry(
                payload: payload,
                status: .pendingTransfer,
                lastTransferFinishedAt: nil,
            ),
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
            WatchTrainingSyncOutboxEntry(
                payload: payload,
                status: .pendingTransfer,
                lastTransferFinishedAt: nil,
            ),
        ])
    }

    func testSuccessfulSystemTransferMarksOutboxEntryAwaitingAckWithoutDeletingIt() throws {
        let payload = try makePayload()
        let transferFinishedAt = Date(timeIntervalSince1970: 20_000)
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(outbox: outbox, session: session, now: { transferFinishedAt })
        try service.enqueueCompletedSession(payload)

        try service.handleSystemTransferFinished(trainingSessionId: payload.id, error: nil)

        XCTAssertEqual(try outbox.loadEntries(), [
            WatchTrainingSyncOutboxEntry(
                payload: payload,
                status: .awaitingAck,
                lastTransferFinishedAt: transferFinishedAt,
            ),
        ])
    }

    func testFailedSystemTransferMarksOutboxEntryPendingForRetry() throws {
        let payload = try makePayload()
        let transferFinishedAt = Date(timeIntervalSince1970: 20_000)
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(outbox: outbox, session: session, now: { transferFinishedAt })
        try service.enqueueCompletedSession(payload)
        try service.handleSystemTransferFinished(trainingSessionId: payload.id, error: nil)

        try service.handleSystemTransferFinished(trainingSessionId: payload.id, error: TestError.transferFailed)

        XCTAssertEqual(try outbox.loadEntries(), [
            WatchTrainingSyncOutboxEntry(
                payload: payload,
                status: .pendingTransfer,
                lastTransferFinishedAt: nil,
            ),
        ])
    }

    func testRetryPendingSessionsTransfersPendingEntriesWhenSessionIsActivated() throws {
        let payload = try makePayload()
        let session = FakeWatchConnectivitySession(activationState: .notActivated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(outbox: outbox, session: session)
        try service.enqueueCompletedSession(payload)

        session.activationState = .activated
        try service.retryPendingSessions()

        XCTAssertEqual(session.transferredUserInfos.count, 1)
        XCTAssertEqual(try decodePayload(from: try XCTUnwrap(session.transferredUserInfos.first)), payload)
    }

    func testActivationCompletionRetriesPendingEntries() throws {
        let payload = try makePayload()
        let session = FakeWatchConnectivitySession(activationState: .notActivated)
        let outbox = makeOutbox()
        try outbox.enqueue(payload)
        let service = WatchTrainingSyncService(outbox: outbox, session: session)

        session.activationState = .activated
        service.handleSessionActivationCompleted()

        XCTAssertEqual(session.transferredUserInfos.count, 1)
        XCTAssertEqual(try decodePayload(from: try XCTUnwrap(session.transferredUserInfos.first)), payload)
    }

    func testAwaitingAckEntryIsRetriedAfterRetryInterval() throws {
        let payload = try makePayload()
        var currentDate = Date(timeIntervalSince1970: 20_000)
        let retryInterval: TimeInterval = 300
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(
            outbox: outbox,
            session: session,
            retryInterval: retryInterval,
            now: { currentDate },
        )
        try service.enqueueCompletedSession(payload)
        try service.handleSystemTransferFinished(trainingSessionId: payload.id, error: nil)
        session.removeAllTransferredUserInfos()

        currentDate = currentDate.addingTimeInterval(retryInterval + 1)
        try service.retryPendingSessions()

        XCTAssertEqual(session.transferredUserInfos.count, 1)
        XCTAssertEqual(try decodePayload(from: try XCTUnwrap(session.transferredUserInfos.first)), payload)
    }

    func testAwaitingAckEntryIsNotRetriedBeforeRetryInterval() throws {
        let payload = try makePayload()
        var currentDate = Date(timeIntervalSince1970: 20_000)
        let retryInterval: TimeInterval = 300
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(
            outbox: outbox,
            session: session,
            retryInterval: retryInterval,
            now: { currentDate },
        )
        try service.enqueueCompletedSession(payload)
        try service.handleSystemTransferFinished(trainingSessionId: payload.id, error: nil)
        session.removeAllTransferredUserInfos()

        currentDate = currentDate.addingTimeInterval(retryInterval - 1)
        try service.retryPendingSessions()

        XCTAssertTrue(session.transferredUserInfos.isEmpty)
    }

    func testAckRemovesMatchingOutboxEntry() throws {
        let payload = try makePayload()
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(outbox: outbox, session: session)
        try service.enqueueCompletedSession(payload)

        try service.handleReceivedUserInfo(makeAckUserInfo(trainingSessionId: payload.id))

        XCTAssertTrue(try outbox.loadEntries().isEmpty)
    }

    func testUnknownAckIsIgnored() throws {
        let payload = try makePayload()
        let unknownTrainingSessionId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000599"))
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(outbox: outbox, session: session)
        try service.enqueueCompletedSession(payload)

        try service.handleReceivedUserInfo(makeAckUserInfo(trainingSessionId: unknownTrainingSessionId))

        XCTAssertEqual(try outbox.loadEntries(), [
            WatchTrainingSyncOutboxEntry(
                payload: payload,
                status: .pendingTransfer,
                lastTransferFinishedAt: nil,
            ),
        ])
    }

    func testDiagnosticsSnapshotIncludesOutboxAndTransferState() throws {
        let payload = try makePayload()
        var currentDate = Date(timeIntervalSince1970: 20_000)
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(
            outbox: outbox,
            session: session,
            now: { currentDate },
        )

        try service.enqueueCompletedSession(payload)
        currentDate = Date(timeIntervalSince1970: 20_010)
        try service.handleSystemTransferFinished(trainingSessionId: payload.id, error: nil)

        XCTAssertEqual(
            service.diagnosticsSnapshot(),
            WatchTrainingSyncDiagnosticsSnapshot(
                activationState: "activated",
                outboxCount: 1,
                pendingTransferCount: 0,
                awaitingAckCount: 1,
                lastActivationCompletedAt: nil,
                lastRetryAt: currentDate.addingTimeInterval(-10),
                lastEnqueuedAt: currentDate.addingTimeInterval(-10),
                lastEnqueuedTrainingSessionId: payload.id,
                lastTransferRequestedAt: currentDate.addingTimeInterval(-10),
                lastTransferRequestedTrainingSessionId: payload.id,
                lastTransferFinishedAt: currentDate,
                lastTransferFinishedTrainingSessionId: payload.id,
                lastTransferErrorDescription: nil,
                lastAckReceivedAt: nil,
                lastAckTrainingSessionId: nil,
                lastOutboxErrorDescription: nil,
            ),
        )
    }

    func testDiagnosticsSnapshotUpdatesAfterAckRemovesOutboxEntry() throws {
        let payload = try makePayload()
        var currentDate = Date(timeIntervalSince1970: 20_000)
        let session = FakeWatchConnectivitySession(activationState: .activated)
        let outbox = makeOutbox()
        let service = WatchTrainingSyncService(
            outbox: outbox,
            session: session,
            now: { currentDate },
        )
        try service.enqueueCompletedSession(payload)

        currentDate = Date(timeIntervalSince1970: 20_020)
        try service.handleReceivedUserInfo(makeAckUserInfo(trainingSessionId: payload.id))

        let snapshot = service.diagnosticsSnapshot()
        XCTAssertEqual(snapshot.outboxCount, 0)
        XCTAssertEqual(snapshot.lastAckReceivedAt, currentDate)
        XCTAssertEqual(snapshot.lastAckTrainingSessionId, payload.id)
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

    private func makeAckUserInfo(trainingSessionId: UUID) throws -> [String: Any] {
        let ack = TrainingSessionSyncAckPayload(
            trainingSessionId: trainingSessionId,
            importedAt: Date(timeIntervalSince1970: 30_000),
        )
        let ackData = try JSONEncoder().encode(ack)
        return [
            WatchTrainingSyncService.userInfoTypeKey: WatchTrainingSyncService.trainingSessionSyncAckUserInfoType,
            WatchTrainingSyncService.userInfoPayloadKey: ackData,
        ]
    }

    private func decodePayload(from userInfo: [String: Any]) throws -> TrainingSessionSyncPayload {
        XCTAssertEqual(
            userInfo[WatchTrainingSyncService.userInfoTypeKey] as? String,
            WatchTrainingSyncService.completedSessionUserInfoType,
        )
        let payloadData = try XCTUnwrap(userInfo[WatchTrainingSyncService.userInfoPayloadKey] as? Data)
        return try JSONDecoder().decode(TrainingSessionSyncPayload.self, from: payloadData)
    }
}

private enum TestError: Error {
    case transferFailed
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

    func removeAllTransferredUserInfos() {
        transferredUserInfos.removeAll()
    }
}

@testable import ShotMarker
import WatchConnectivity
import XCTest

final class PhoneWatchSyncServiceTests: XCTestCase {
    func testStartActivatesSupportedSession() {
        let session = FakePhoneWatchConnectivitySession(isSupported: true)
        let service = PhoneWatchSyncService(
            importer: SpyTrainingSessionImporter(),
            session: session,
        )

        service.start()

        XCTAssertEqual(session.setDelegateCallCount, 1)
        XCTAssertTrue(session.delegate === service)
        XCTAssertEqual(session.activateCallCount, 1)
    }

    func testStartDoesNotActivateUnsupportedSession() {
        let session = FakePhoneWatchConnectivitySession(isSupported: false)
        let service = PhoneWatchSyncService(
            importer: SpyTrainingSessionImporter(),
            session: session,
        )

        service.start()

        XCTAssertEqual(session.setDelegateCallCount, 0)
        XCTAssertEqual(session.activateCallCount, 0)
    }

    func testCompletedTrainingSessionUserInfoImportsPostsNotificationAndTransfersAck() throws {
        let payload = try makePayload()
        let importer = SpyTrainingSessionImporter()
        let session = FakePhoneWatchConnectivitySession(isSupported: true)
        let notificationCenter = NotificationCenter()
        let notificationExpectation = expectation(description: "training sessions did change")
        let observer = notificationCenter.addObserver(
            forName: .trainingSessionsDidChange,
            object: nil,
            queue: .main,
        ) { _ in
            notificationExpectation.fulfill()
        }
        defer {
            notificationCenter.removeObserver(observer)
        }
        let service = PhoneWatchSyncService(
            importer: importer,
            session: session,
            notificationCenter: notificationCenter,
            now: { Date(timeIntervalSince1970: 20000) },
        )

        service.handleReceivedUserInfo(try makeCompletedTrainingSessionUserInfo(payload: payload))

        wait(for: [notificationExpectation], timeout: 1)
        XCTAssertEqual(importer.importedPayloads, [payload])
        XCTAssertEqual(session.transferredUserInfos.count, 1)
        let ackUserInfo = try XCTUnwrap(session.transferredUserInfos.first)
        XCTAssertEqual(
            ackUserInfo[PhoneWatchSyncService.userInfoTypeKey] as? String,
            PhoneWatchSyncService.trainingSessionSyncAckUserInfoType,
        )
        let ackData = try XCTUnwrap(ackUserInfo[PhoneWatchSyncService.userInfoPayloadKey] as? Data)
        XCTAssertEqual(
            try JSONDecoder().decode(TrainingSessionSyncAckPayload.self, from: ackData),
            TrainingSessionSyncAckPayload(
                trainingSessionId: payload.id,
                importedAt: Date(timeIntervalSince1970: 20000),
            ),
        )
    }

    func testDuplicateCompletedTrainingSessionUserInfoImportsAndAcksEachArrival() throws {
        let payload = try makePayload()
        let importer = SpyTrainingSessionImporter()
        let session = FakePhoneWatchConnectivitySession(isSupported: true)
        let service = PhoneWatchSyncService(importer: importer, session: session)
        let userInfo = try makeCompletedTrainingSessionUserInfo(payload: payload)

        service.handleReceivedUserInfo(userInfo)
        service.handleReceivedUserInfo(userInfo)

        XCTAssertEqual(importer.importedPayloads, [payload, payload])
        XCTAssertEqual(session.transferredUserInfos.count, 2)
    }

    func testUnknownUserInfoTypeDoesNothing() throws {
        let importer = SpyTrainingSessionImporter()
        let session = FakePhoneWatchConnectivitySession(isSupported: true)
        let service = PhoneWatchSyncService(importer: importer, session: session)

        service.handleReceivedUserInfo([
            PhoneWatchSyncService.userInfoTypeKey: "unknown",
            PhoneWatchSyncService.userInfoPayloadKey: Data(),
        ])

        XCTAssertEqual(importer.importedPayloads, [])
        XCTAssertEqual(session.transferredUserInfos.count, 0)
    }

    func testInvalidPayloadDoesNotImportOrAck() {
        let importer = SpyTrainingSessionImporter()
        let session = FakePhoneWatchConnectivitySession(isSupported: true)
        let service = PhoneWatchSyncService(importer: importer, session: session)

        service.handleReceivedUserInfo([
            PhoneWatchSyncService.userInfoTypeKey: PhoneWatchSyncService.completedTrainingSessionUserInfoType,
            PhoneWatchSyncService.userInfoPayloadKey: Data("invalid".utf8),
        ])

        XCTAssertEqual(importer.importedPayloads, [])
        XCTAssertEqual(session.transferredUserInfos.count, 0)
    }

    func testImportFailureDoesNotPostNotificationOrAck() throws {
        let importer = SpyTrainingSessionImporter(error: SyncImportError.failed)
        let session = FakePhoneWatchConnectivitySession(isSupported: true)
        let notificationCenter = NotificationCenter()
        let service = PhoneWatchSyncService(
            importer: importer,
            session: session,
            notificationCenter: notificationCenter,
        )
        let payload = try makePayload()

        service.handleReceivedUserInfo(try makeCompletedTrainingSessionUserInfo(payload: payload))

        XCTAssertEqual(importer.importedPayloads, [payload])
        XCTAssertEqual(session.transferredUserInfos.count, 0)
    }

    private func makeCompletedTrainingSessionUserInfo(payload: TrainingSessionSyncPayload) throws -> [String: Any] {
        [
            PhoneWatchSyncService.userInfoTypeKey: PhoneWatchSyncService.completedTrainingSessionUserInfoType,
            PhoneWatchSyncService.userInfoPayloadKey: try JSONEncoder().encode(payload),
        ]
    }

    private func makePayload() throws -> TrainingSessionSyncPayload {
        TrainingSessionSyncPayload(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000801")),
            startedAt: Date(timeIntervalSince1970: 10000),
            endedAt: Date(timeIntervalSince1970: 10600),
            events: [
                ShotMarkerEventSyncPayload(
                    id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000802")),
                    markedAt: Date(timeIntervalSince1970: 10120),
                ),
            ],
        )
    }
}

private enum SyncImportError: Error {
    case failed
}

private final class SpyTrainingSessionImporter: TrainingSessionImporting {
    private let error: Error?
    private(set) var importedPayloads: [TrainingSessionSyncPayload] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func `import`(_ payload: TrainingSessionSyncPayload) throws {
        importedPayloads.append(payload)

        if let error {
            throw error
        }
    }
}

private final class FakePhoneWatchConnectivitySession: PhoneWatchConnectivitySessionProtocol {
    let isSupported: Bool
    private(set) var setDelegateCallCount = 0
    private(set) var activateCallCount = 0
    private(set) var transferredUserInfos: [[String: Any]] = []
    weak var delegate: WCSessionDelegate?

    init(isSupported: Bool) {
        self.isSupported = isSupported
    }

    func setDelegate(_ delegate: WCSessionDelegate) {
        setDelegateCallCount += 1
        self.delegate = delegate
    }

    func activate() {
        activateCallCount += 1
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        transferredUserInfos.append(userInfo)
    }
}

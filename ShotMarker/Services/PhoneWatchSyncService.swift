import Foundation
import WatchConnectivity

protocol PhoneWatchConnectivitySessionProtocol: AnyObject {
    var isSupported: Bool { get }

    func setDelegate(_ delegate: WCSessionDelegate)
    func activate()
    func transferUserInfo(_ userInfo: [String: Any])
}

extension Notification.Name {
    static let trainingSessionsDidChange = Notification.Name("trainingSessionsDidChange")
}

final class PhoneWatchSyncService: NSObject, WCSessionDelegate {
    static let userInfoTypeKey = "type"
    static let userInfoPayloadKey = "payload"
    static let completedTrainingSessionUserInfoType = "completedTrainingSession"
    static let trainingSessionSyncAckUserInfoType = "trainingSessionSyncAck"

    private let importer: TrainingSessionImporting
    private let session: PhoneWatchConnectivitySessionProtocol
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        importer: TrainingSessionImporting,
        session: PhoneWatchConnectivitySessionProtocol? = nil,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
    ) {
        self.importer = importer
        self.session = session ?? PhoneWatchConnectivitySessionAdapter()
        self.notificationCenter = notificationCenter
        self.now = now
    }

    func start() {
        guard session.isSupported else {
            return
        }

        session.setDelegate(self)
        session.activate()
    }

    func handleReceivedUserInfo(_ userInfo: [String: Any]) {
        guard userInfo[Self.userInfoTypeKey] as? String == Self.completedTrainingSessionUserInfoType else {
            return
        }

        guard
            let payloadData = userInfo[Self.userInfoPayloadKey] as? Data,
            let payload = try? decoder.decode(TrainingSessionSyncPayload.self, from: payloadData)
        else {
            return
        }

        do {
            try importer.import(payload)
            notificationCenter.post(name: .trainingSessionsDidChange, object: nil)
            try transferAck(for: payload)
        } catch {
            return
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleReceivedUserInfo(userInfo)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?,
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        self.session.activate()
    }

    private func transferAck(for payload: TrainingSessionSyncPayload) throws {
        let ack = TrainingSessionSyncAckPayload(
            trainingSessionId: payload.id,
            importedAt: now(),
        )
        let ackData = try encoder.encode(ack)
        session.transferUserInfo([
            Self.userInfoTypeKey: Self.trainingSessionSyncAckUserInfoType,
            Self.userInfoPayloadKey: ackData,
        ])
    }
}

private final class PhoneWatchConnectivitySessionAdapter: PhoneWatchConnectivitySessionProtocol {
    private let session: WCSession

    init(session: WCSession = .default) {
        self.session = session
    }

    var isSupported: Bool {
        WCSession.isSupported()
    }

    func setDelegate(_ delegate: WCSessionDelegate) {
        session.delegate = delegate
    }

    func activate() {
        session.activate()
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        session.transferUserInfo(userInfo)
    }
}

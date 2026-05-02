import Foundation
import WatchConnectivity

protocol PhoneWatchConnectivitySessionProtocol: AnyObject {
    var isSupported: Bool { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var activationStateDescription: String { get }

    func setDelegate(_ delegate: WCSessionDelegate)
    func activate()
    func transferUserInfo(_ userInfo: [String: Any])
}

extension Notification.Name {
    static let trainingSessionsDidChange = Notification.Name("trainingSessionsDidChange")
}

struct PhoneWatchSyncDiagnosticsSnapshot: Equatable {
    let isSupported: Bool
    let isPaired: Bool
    let isWatchAppInstalled: Bool
    let activationState: String
    let lastActivationCompletedAt: Date?
    let lastActivationErrorDescription: String?
    let lastReceivedPayloadAt: Date?
    let lastReceivedTrainingSessionId: UUID?
    let lastImportErrorDescription: String?
    let lastAckSentAt: Date?
    let lastAckTrainingSessionId: UUID?
    let lastAckErrorDescription: String?
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
    private var lastActivationCompletedAt: Date?
    private var lastActivationErrorDescription: String?
    private var lastReceivedPayloadAt: Date?
    private var lastReceivedTrainingSessionId: UUID?
    private var lastImportErrorDescription: String?
    private var lastAckSentAt: Date?
    private var lastAckTrainingSessionId: UUID?
    private var lastAckErrorDescription: String?

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
            lastActivationErrorDescription = "WCSession is not supported"
            return
        }

        session.setDelegate(self)
        session.activate()
    }

    func diagnosticsSnapshot() -> PhoneWatchSyncDiagnosticsSnapshot {
        PhoneWatchSyncDiagnosticsSnapshot(
            isSupported: session.isSupported,
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            activationState: session.activationStateDescription,
            lastActivationCompletedAt: lastActivationCompletedAt,
            lastActivationErrorDescription: lastActivationErrorDescription,
            lastReceivedPayloadAt: lastReceivedPayloadAt,
            lastReceivedTrainingSessionId: lastReceivedTrainingSessionId,
            lastImportErrorDescription: lastImportErrorDescription,
            lastAckSentAt: lastAckSentAt,
            lastAckTrainingSessionId: lastAckTrainingSessionId,
            lastAckErrorDescription: lastAckErrorDescription,
        )
    }

    func handleReceivedUserInfo(_ userInfo: [String: Any]) {
        guard userInfo[Self.userInfoTypeKey] as? String == Self.completedTrainingSessionUserInfoType else {
            return
        }

        guard
            let payloadData = userInfo[Self.userInfoPayloadKey] as? Data,
            let payload = try? decoder.decode(TrainingSessionSyncPayload.self, from: payloadData)
        else {
            lastImportErrorDescription = "Unable to decode completed training session payload"
            return
        }

        lastReceivedPayloadAt = now()
        lastReceivedTrainingSessionId = payload.id

        do {
            try importer.import(payload)
        } catch {
            lastImportErrorDescription = String(describing: error)
            return
        }

        lastImportErrorDescription = nil
        notificationCenter.post(name: .trainingSessionsDidChange, object: nil)

        do {
            try transferAck(for: payload)
        } catch {
            lastAckErrorDescription = String(describing: error)
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
    ) {
        lastActivationCompletedAt = now()
        lastActivationErrorDescription = error.map { String(describing: $0) }
    }

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
        lastAckSentAt = ack.importedAt
        lastAckTrainingSessionId = payload.id
        lastAckErrorDescription = nil
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

    var isPaired: Bool {
        session.isPaired
    }

    var isWatchAppInstalled: Bool {
        session.isWatchAppInstalled
    }

    var activationStateDescription: String {
        session.activationState.diagnosticsDescription
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

private extension WCSessionActivationState {
    var diagnosticsDescription: String {
        switch self {
        case .notActivated:
            "notActivated"
        case .inactive:
            "inactive"
        case .activated:
            "activated"
        @unknown default:
            "unknown"
        }
    }
}

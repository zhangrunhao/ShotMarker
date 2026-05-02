import Foundation
#if canImport(WatchConnectivity)
    import WatchConnectivity
#endif

protocol WatchTrainingSyncServiceProtocol {
    func enqueueCompletedSession(_ payload: TrainingSessionSyncPayload) throws
}

enum WatchConnectivitySessionActivationState: Equatable {
    case notActivated
    case inactive
    case activated
}

protocol WatchConnectivitySessionProtocol: AnyObject {
    var activationState: WatchConnectivitySessionActivationState { get }

    func activate()
    func transferUserInfo(_ userInfo: [String: Any])
}

final class WatchTrainingSyncService: WatchTrainingSyncServiceProtocol {
    static let userInfoTypeKey = "type"
    static let userInfoPayloadKey = "payload"
    static let completedSessionUserInfoType = "completedTrainingSession"

    private let outbox: WatchTrainingSyncOutbox
    private let session: WatchConnectivitySessionProtocol
    private let encoder = JSONEncoder()

    init(
        outbox: WatchTrainingSyncOutbox = WatchTrainingSyncOutbox(),
        session: WatchConnectivitySessionProtocol? = nil,
    ) {
        let resolvedSession = session ?? Self.makeDefaultSession()
        self.outbox = outbox
        self.session = resolvedSession

        #if canImport(WatchConnectivity)
            if let adapter = resolvedSession as? WCSessionWatchConnectivitySessionAdapter {
                adapter.onTransferFinished = { [weak self] trainingSessionId, error in
                    try? self?.handleSystemTransferFinished(
                        trainingSessionId: trainingSessionId,
                        error: error,
                    )
                }
            }
        #endif

        self.session.activate()
    }

    func enqueueCompletedSession(_ payload: TrainingSessionSyncPayload) throws {
        try outbox.enqueue(payload)

        guard session.activationState == .activated else {
            return
        }

        let payloadData = try encoder.encode(payload)
        session.transferUserInfo([
            Self.userInfoTypeKey: Self.completedSessionUserInfoType,
            Self.userInfoPayloadKey: payloadData,
        ])
    }

    func handleSystemTransferFinished(trainingSessionId: UUID, error: Error?) throws {
        guard error == nil else {
            return
        }

        try outbox.markAwaitingAck(trainingSessionId: trainingSessionId)
    }

    private static func makeDefaultSession() -> WatchConnectivitySessionProtocol {
        #if canImport(WatchConnectivity)
            WCSessionWatchConnectivitySessionAdapter()
        #else
            UnavailableWatchConnectivitySession()
        #endif
    }
}

#if canImport(WatchConnectivity)
    final class WCSessionWatchConnectivitySessionAdapter: NSObject, WatchConnectivitySessionProtocol, WCSessionDelegate {
        var onTransferFinished: ((UUID, Error?) -> Void)?

        private let session: WCSession
        private let decoder = JSONDecoder()

        init(session: WCSession = .default) {
            self.session = session
        }

        var activationState: WatchConnectivitySessionActivationState {
            switch session.activationState {
            case .notActivated:
                .notActivated
            case .inactive:
                .inactive
            case .activated:
                .activated
            @unknown default:
                .notActivated
            }
        }

        func activate() {
            guard WCSession.isSupported() else {
                return
            }

            session.delegate = self
            session.activate()
        }

        func transferUserInfo(_ userInfo: [String: Any]) {
            session.transferUserInfo(userInfo)
        }

        func session(
            _ session: WCSession,
            activationDidCompleteWith activationState: WCSessionActivationState,
            error: Error?,
        ) {}

        func session(
            _ session: WCSession,
            didFinish userInfoTransfer: WCSessionUserInfoTransfer,
            error: Error?,
        ) {
            guard
                let payloadData = userInfoTransfer.userInfo[WatchTrainingSyncService.userInfoPayloadKey] as? Data,
                let payload = try? decoder.decode(TrainingSessionSyncPayload.self, from: payloadData)
            else {
                return
            }

            onTransferFinished?(payload.id, error)
        }
    }
#else
    private final class UnavailableWatchConnectivitySession: WatchConnectivitySessionProtocol {
        let activationState: WatchConnectivitySessionActivationState = .notActivated

        func activate() {}
        func transferUserInfo(_ userInfo: [String: Any]) {}
    }
#endif

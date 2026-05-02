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
    static let trainingSessionSyncAckUserInfoType = "trainingSessionSyncAck"

    private let outbox: WatchTrainingSyncOutbox
    private let session: WatchConnectivitySessionProtocol
    private let retryInterval: TimeInterval
    private let now: () -> Date
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        outbox: WatchTrainingSyncOutbox = WatchTrainingSyncOutbox(),
        session: WatchConnectivitySessionProtocol? = nil,
        retryInterval: TimeInterval = 300,
        now: @escaping () -> Date = Date.init,
    ) {
        let resolvedSession = session ?? Self.makeDefaultSession()
        self.outbox = outbox
        self.session = resolvedSession
        self.retryInterval = retryInterval
        self.now = now

        #if canImport(WatchConnectivity)
            if let adapter = resolvedSession as? WCSessionWatchConnectivitySessionAdapter {
                adapter.onActivationCompleted = { [weak self] in
                    self?.handleSessionActivationCompleted()
                }
                adapter.onTransferFinished = { [weak self] trainingSessionId, error in
                    try? self?.handleSystemTransferFinished(
                        trainingSessionId: trainingSessionId,
                        error: error,
                    )
                }
                adapter.onUserInfoReceived = { [weak self] userInfo in
                    try? self?.handleReceivedUserInfo(userInfo)
                }
            }
        #endif

        self.session.activate()
        try? retryPendingSessions()
    }

    func enqueueCompletedSession(_ payload: TrainingSessionSyncPayload) throws {
        try outbox.enqueue(payload)

        guard session.activationState == .activated else {
            return
        }

        try transfer(payload)
    }

    func retryPendingSessions() throws {
        guard session.activationState == .activated else {
            return
        }

        let currentDate = now()
        let entries = try outbox.loadEntries()
        for entry in entries where shouldRetry(entry, at: currentDate) {
            try transfer(entry.payload)
        }
    }

    func handleSessionActivationCompleted() {
        try? retryPendingSessions()
    }

    func handleReceivedUserInfo(_ userInfo: [String: Any]) throws {
        guard userInfo[Self.userInfoTypeKey] as? String == Self.trainingSessionSyncAckUserInfoType else {
            return
        }

        guard
            let payloadData = userInfo[Self.userInfoPayloadKey] as? Data,
            let ack = try? decoder.decode(TrainingSessionSyncAckPayload.self, from: payloadData)
        else {
            return
        }

        try outbox.remove(trainingSessionId: ack.trainingSessionId)
    }

    func handleSystemTransferFinished(trainingSessionId: UUID, error: Error?) throws {
        guard error == nil else {
            try outbox.markPendingTransfer(trainingSessionId: trainingSessionId)
            return
        }

        try outbox.markAwaitingAck(trainingSessionId: trainingSessionId, lastTransferFinishedAt: now())
    }

    private func transfer(_ payload: TrainingSessionSyncPayload) throws {
        let payloadData = try encoder.encode(payload)
        session.transferUserInfo([
            Self.userInfoTypeKey: Self.completedSessionUserInfoType,
            Self.userInfoPayloadKey: payloadData,
        ])
    }

    private func shouldRetry(_ entry: WatchTrainingSyncOutboxEntry, at currentDate: Date) -> Bool {
        switch entry.status {
        case .pendingTransfer:
            return true
        case .awaitingAck:
            guard let lastTransferFinishedAt = entry.lastTransferFinishedAt else {
                return true
            }

            return currentDate.timeIntervalSince(lastTransferFinishedAt) >= retryInterval
        }
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
        var onActivationCompleted: (() -> Void)?
        var onTransferFinished: ((UUID, Error?) -> Void)?
        var onUserInfoReceived: (([String: Any]) -> Void)?

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
        ) {
            guard error == nil, activationState == .activated else {
                return
            }

            onActivationCompleted?()
        }

        func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
            onUserInfoReceived?(userInfo)
        }

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

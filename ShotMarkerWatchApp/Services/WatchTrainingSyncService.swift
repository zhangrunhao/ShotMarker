import Foundation
#if canImport(WatchConnectivity)
    import WatchConnectivity
#endif

protocol WatchTrainingSyncServiceProtocol {
    func enqueueCompletedSession(_ payload: TrainingSessionSyncPayload) throws
    func diagnosticsSnapshot() -> WatchTrainingSyncDiagnosticsSnapshot
}

enum WatchConnectivitySessionActivationState: Equatable {
    case notActivated
    case inactive
    case activated

    var diagnosticsDescription: String {
        switch self {
        case .notActivated:
            "notActivated"
        case .inactive:
            "inactive"
        case .activated:
            "activated"
        }
    }
}

protocol WatchConnectivitySessionProtocol: AnyObject {
    var activationState: WatchConnectivitySessionActivationState { get }

    func activate()
    func transferUserInfo(_ userInfo: [String: Any])
}

struct WatchTrainingSyncDiagnosticsSnapshot: Equatable {
    let activationState: String
    let outboxCount: Int
    let pendingTransferCount: Int
    let awaitingAckCount: Int
    let lastActivationCompletedAt: Date?
    let lastRetryAt: Date?
    let lastEnqueuedAt: Date?
    let lastEnqueuedTrainingSessionId: UUID?
    let lastTransferRequestedAt: Date?
    let lastTransferRequestedTrainingSessionId: UUID?
    let lastTransferFinishedAt: Date?
    let lastTransferFinishedTrainingSessionId: UUID?
    let lastTransferErrorDescription: String?
    let lastAckReceivedAt: Date?
    let lastAckTrainingSessionId: UUID?
    let lastOutboxErrorDescription: String?
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
    private var lastActivationCompletedAt: Date?
    private var lastRetryAt: Date?
    private var lastEnqueuedAt: Date?
    private var lastEnqueuedTrainingSessionId: UUID?
    private var lastTransferRequestedAt: Date?
    private var lastTransferRequestedTrainingSessionId: UUID?
    private var lastTransferFinishedAt: Date?
    private var lastTransferFinishedTrainingSessionId: UUID?
    private var lastTransferErrorDescription: String?
    private var lastAckReceivedAt: Date?
    private var lastAckTrainingSessionId: UUID?
    private var lastOutboxErrorDescription: String?

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
        lastEnqueuedAt = now()
        lastEnqueuedTrainingSessionId = payload.id
        lastOutboxErrorDescription = nil

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
        lastRetryAt = currentDate
        let entries = try outbox.loadEntries()
        lastOutboxErrorDescription = nil
        for entry in entries where shouldRetry(entry, at: currentDate) {
            try transfer(entry.payload)
        }
    }

    func handleSessionActivationCompleted() {
        lastActivationCompletedAt = now()
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

        lastAckReceivedAt = now()
        lastAckTrainingSessionId = ack.trainingSessionId

        do {
            try outbox.remove(trainingSessionId: ack.trainingSessionId)
            lastOutboxErrorDescription = nil
        } catch {
            lastOutboxErrorDescription = String(describing: error)
            throw error
        }
    }

    func handleSystemTransferFinished(trainingSessionId: UUID, error: Error?) throws {
        let currentDate = now()
        lastTransferFinishedAt = currentDate
        lastTransferFinishedTrainingSessionId = trainingSessionId

        guard error == nil else {
            lastTransferErrorDescription = String(describing: error!)
            try outbox.markPendingTransfer(trainingSessionId: trainingSessionId)
            return
        }

        lastTransferErrorDescription = nil
        try outbox.markAwaitingAck(trainingSessionId: trainingSessionId, lastTransferFinishedAt: currentDate)
        lastOutboxErrorDescription = nil
    }

    func diagnosticsSnapshot() -> WatchTrainingSyncDiagnosticsSnapshot {
        let entries: [WatchTrainingSyncOutboxEntry]
        let outboxErrorDescription: String?

        do {
            entries = try outbox.loadEntries()
            outboxErrorDescription = lastOutboxErrorDescription
        } catch {
            entries = []
            outboxErrorDescription = String(describing: error)
        }

        return WatchTrainingSyncDiagnosticsSnapshot(
            activationState: session.activationState.diagnosticsDescription,
            outboxCount: entries.count,
            pendingTransferCount: entries.filter { $0.status == .pendingTransfer }.count,
            awaitingAckCount: entries.filter { $0.status == .awaitingAck }.count,
            lastActivationCompletedAt: lastActivationCompletedAt,
            lastRetryAt: lastRetryAt,
            lastEnqueuedAt: lastEnqueuedAt,
            lastEnqueuedTrainingSessionId: lastEnqueuedTrainingSessionId,
            lastTransferRequestedAt: lastTransferRequestedAt,
            lastTransferRequestedTrainingSessionId: lastTransferRequestedTrainingSessionId,
            lastTransferFinishedAt: lastTransferFinishedAt,
            lastTransferFinishedTrainingSessionId: lastTransferFinishedTrainingSessionId,
            lastTransferErrorDescription: lastTransferErrorDescription,
            lastAckReceivedAt: lastAckReceivedAt,
            lastAckTrainingSessionId: lastAckTrainingSessionId,
            lastOutboxErrorDescription: outboxErrorDescription,
        )
    }

    private func transfer(_ payload: TrainingSessionSyncPayload) throws {
        let payloadData = try encoder.encode(payload)
        session.transferUserInfo([
            Self.userInfoTypeKey: Self.completedSessionUserInfoType,
            Self.userInfoPayloadKey: payloadData,
        ])
        lastTransferRequestedAt = now()
        lastTransferRequestedTrainingSessionId = payload.id
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

import Foundation

protocol TrainingSessionImporting {
    func `import`(_ payload: TrainingSessionSyncPayload) throws
}

final class TrainingSessionImporter: TrainingSessionImporting {
    private let store: TrainingSessionStoreProtocol

    init(store: TrainingSessionStoreProtocol) {
        self.store = store
    }

    func `import`(_ payload: TrainingSessionSyncPayload) throws {
        var sessions = try store.loadTrainingSessions()
        let session = TrainingSession(
            id: payload.id,
            startedAt: payload.startedAt,
            endedAt: payload.endedAt,
            events: payload.events.map { event in
                ShotMarkerEvent(id: event.id, markedAt: event.markedAt)
            },
        )

        if let index = sessions.firstIndex(where: { $0.id == payload.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }

        try store.saveTrainingSessions(sessions)
    }
}

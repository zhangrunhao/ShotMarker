import Foundation

struct TrainingSessionSyncPayload: Codable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let events: [ShotMarkerEventSyncPayload]
}

struct ShotMarkerEventSyncPayload: Codable, Equatable {
    let id: UUID
    let markedAt: Date
}

struct TrainingSessionSyncAckPayload: Codable, Equatable {
    let trainingSessionId: UUID
    let importedAt: Date
}

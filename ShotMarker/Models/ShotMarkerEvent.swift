import Foundation

struct ShotMarkerEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let markedAt: Date
    let source: MarkerSource

    init(id: UUID = UUID(), markedAt: Date, source: MarkerSource) {
        self.id = id
        self.markedAt = markedAt
        self.source = source
    }
}

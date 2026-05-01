import Foundation

struct ShotMarkerEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let markedAt: Date

    init(id: UUID = UUID(), markedAt: Date) {
        self.id = id
        self.markedAt = markedAt
    }
}

import Foundation

struct TrainingSession: Identifiable, Codable, Equatable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date
    var events: [ShotMarkerEvent]

    var markerCount: Int {
        events.count
    }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        events: [ShotMarkerEvent],
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
    }
}

#if DEBUG
    extension TrainingSession {
        static let previewSessions: [TrainingSession] = {
            let now = Date()

            return [
                TrainingSession(
                    startedAt: now.addingTimeInterval(-2400),
                    endedAt: now.addingTimeInterval(-600),
                    events: [
                        ShotMarkerEvent(markedAt: now.addingTimeInterval(-2100)),
                        ShotMarkerEvent(markedAt: now.addingTimeInterval(-1700)),
                        ShotMarkerEvent(markedAt: now.addingTimeInterval(-1200)),
                    ],
                ),
                TrainingSession(
                    startedAt: now.addingTimeInterval(-90000),
                    endedAt: now.addingTimeInterval(-87300),
                    events: [
                        ShotMarkerEvent(markedAt: now.addingTimeInterval(-89520)),
                        ShotMarkerEvent(markedAt: now.addingTimeInterval(-88740)),
                    ],
                ),
                TrainingSession(
                    startedAt: now.addingTimeInterval(-176_400),
                    endedAt: now.addingTimeInterval(-174_900),
                    events: [
                        ShotMarkerEvent(markedAt: now.addingTimeInterval(-175_680)),
                    ],
                ),
            ]
        }()
    }
#endif

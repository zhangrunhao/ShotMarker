import Foundation

struct TrainingSession: Identifiable, Codable, Equatable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date
    var events: [ShotMarkerEvent]

    var markerCount: Int {
        events.count
    }

    var markerTimeRange: (startedAt: Date, endedAt: Date) {
        let markerDates = events.map(\.markedAt)

        guard let firstMarkerDate = markerDates.min(), let lastMarkerDate = markerDates.max() else {
            return (startedAt, endedAt)
        }

        return (firstMarkerDate, lastMarkerDate)
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

    static func merged(_ sessions: [TrainingSession]) -> TrainingSession? {
        let orderedSessions = sessions.sorted { lhs, rhs in
            let lhsRange = lhs.markerTimeRange
            let rhsRange = rhs.markerTimeRange

            if lhsRange.startedAt == rhsRange.startedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhsRange.startedAt < rhsRange.startedAt
        }

        guard let firstSession = orderedSessions.first else {
            return nil
        }

        let ranges = orderedSessions.map(\.markerTimeRange)
        let startedAt = ranges.map(\.startedAt).min() ?? firstSession.startedAt
        let endedAt = ranges.map(\.endedAt).max() ?? firstSession.endedAt
        let events = orderedSessions
            .flatMap(\.events)
            .sorted { $0.markedAt < $1.markedAt }

        return TrainingSession(
            id: firstSession.id,
            startedAt: startedAt,
            endedAt: endedAt,
            events: events,
        )
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

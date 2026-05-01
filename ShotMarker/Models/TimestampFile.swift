import Foundation

struct TimestampFile: Identifiable, Codable, Equatable {
    let id: UUID
    var trainingDate: Date
    var startedAt: Date
    var endedAt: Date?
    var events: [ShotMarkerEvent]
    var syncStatus: SyncStatus
    var highlightStatus: HighlightStatus

    var markerCount: Int {
        events.count
    }

    init(
        id: UUID = UUID(),
        trainingDate: Date,
        startedAt: Date,
        endedAt: Date? = nil,
        events: [ShotMarkerEvent],
        syncStatus: SyncStatus,
        highlightStatus: HighlightStatus
    ) {
        self.id = id
        self.trainingDate = trainingDate
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
        self.syncStatus = syncStatus
        self.highlightStatus = highlightStatus
    }
}

#if DEBUG
extension TimestampFile {
    static let previewFiles: [TimestampFile] = [
        TimestampFile(
            trainingDate: Date(),
            startedAt: Date().addingTimeInterval(-2_400),
            endedAt: Date().addingTimeInterval(-600),
            events: [
                ShotMarkerEvent(markedAt: Date().addingTimeInterval(-2_100), source: .watch),
                ShotMarkerEvent(markedAt: Date().addingTimeInterval(-1_700), source: .watch),
                ShotMarkerEvent(markedAt: Date().addingTimeInterval(-1_200), source: .watch)
            ],
            syncStatus: .synced,
            highlightStatus: .notClipped
        )
    ]
}
#endif

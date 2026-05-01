import Foundation
import Combine

struct TimestampFileRowViewData: Identifiable, Equatable {
    let id: UUID
    let trainingDate: Date
    let startedAt: Date
    let markerCount: Int
    let syncStatus: SyncStatus
    let highlightStatus: HighlightStatus

    init(
        id: UUID,
        trainingDate: Date,
        startedAt: Date,
        markerCount: Int,
        syncStatus: SyncStatus,
        highlightStatus: HighlightStatus
    ) {
        self.id = id
        self.trainingDate = trainingDate
        self.startedAt = startedAt
        self.markerCount = markerCount
        self.syncStatus = syncStatus
        self.highlightStatus = highlightStatus
    }

    init(file: TimestampFile) {
        self.init(
            id: file.id,
            trainingDate: file.trainingDate,
            startedAt: file.startedAt,
            markerCount: file.markerCount,
            syncStatus: file.syncStatus,
            highlightStatus: file.highlightStatus
        )
    }
}

@MainActor
final class TimestampListViewModel: ObservableObject {
    @Published private(set) var rows: [TimestampFileRowViewData] = []
    @Published private(set) var errorMessage: String?

    private let store: TimestampFileStoreProtocol

    var isEmpty: Bool {
        rows.isEmpty
    }

    init(store: TimestampFileStoreProtocol) {
        self.store = store
    }

    func load() {
        do {
            rows = try store.loadTimestampFiles()
                .sorted { $0.startedAt > $1.startedAt }
                .map(TimestampFileRowViewData.init(file:))
            errorMessage = nil
        } catch {
            rows = []
            errorMessage = "无法读取训练记录"
        }
    }
}

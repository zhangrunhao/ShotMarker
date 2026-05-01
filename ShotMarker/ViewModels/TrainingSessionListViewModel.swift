import Foundation
import Combine

struct TrainingSessionRowViewData: Identifiable, Equatable {
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

    init(session: TrainingSession) {
        self.init(
            id: session.id,
            trainingDate: session.trainingDate,
            startedAt: session.startedAt,
            markerCount: session.markerCount,
            syncStatus: session.syncStatus,
            highlightStatus: session.highlightStatus
        )
    }
}

@MainActor
final class TrainingSessionListViewModel: ObservableObject {
    @Published private(set) var rows: [TrainingSessionRowViewData] = []
    @Published private(set) var errorMessage: String?

    private let store: TrainingSessionStoreProtocol

    var isEmpty: Bool {
        rows.isEmpty
    }

    init(store: TrainingSessionStoreProtocol) {
        self.store = store
    }

    func load() {
        do {
            rows = try store.loadTrainingSessions()
                .sorted { $0.startedAt > $1.startedAt }
                .map(TrainingSessionRowViewData.init(session:))
            errorMessage = nil
        } catch {
            rows = []
            errorMessage = "无法读取训练记录"
        }
    }
}

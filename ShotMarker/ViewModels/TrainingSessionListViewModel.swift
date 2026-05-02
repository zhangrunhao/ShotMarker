import Combine
import Foundation

struct TrainingSessionRowViewData: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let markerCount: Int

    init(
        id: UUID,
        startedAt: Date,
        markerCount: Int,
    ) {
        self.id = id
        self.startedAt = startedAt
        self.markerCount = markerCount
    }

    init(session: TrainingSession) {
        self.init(
            id: session.id,
            startedAt: session.startedAt,
            markerCount: session.markerCount,
        )
    }
}

@MainActor
final class TrainingSessionListViewModel: ObservableObject {
    @Published private(set) var rows: [TrainingSessionRowViewData] = []
    @Published private(set) var errorMessage: String?

    private let store: TrainingSessionStoreProtocol
    private let notificationCenter: NotificationCenter
    private var trainingSessionsDidChangeObserver: NSObjectProtocol?

    var isEmpty: Bool {
        rows.isEmpty
    }

    init(store: TrainingSessionStoreProtocol, notificationCenter: NotificationCenter = .default) {
        self.store = store
        self.notificationCenter = notificationCenter
        trainingSessionsDidChangeObserver = notificationCenter.addObserver(
            forName: .trainingSessionsDidChange,
            object: nil,
            queue: nil,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.load()
            }
        }
    }

    deinit {
        if let trainingSessionsDidChangeObserver {
            notificationCenter.removeObserver(trainingSessionsDidChangeObserver)
        }
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

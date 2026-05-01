import Combine
import Foundation

enum WatchTrainingState: Equatable {
    case ended
    case started
}

@MainActor
final class WatchTrainingViewModel: ObservableObject {
    @Published private(set) var state: WatchTrainingState = .ended
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var markers: [Date] = []

    private let now: () -> Date

    var buttonTitle: String {
        switch state {
        case .ended:
            return "开始"
        case .started:
            return "结束"
        }
    }

    var markerCount: Int {
        markers.count
    }

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func handleLongPress() {
        switch state {
        case .ended:
            startedAt = now()
            endedAt = nil
            markers = []
            state = .started
        case .started:
            endedAt = now()
            state = .ended
        }
    }
}

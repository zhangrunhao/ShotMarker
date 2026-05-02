import Combine
import Foundation
import SwiftUI

enum WatchTrainingState: Equatable {
    case notTraining
    case training
}

@MainActor
final class WatchTrainingViewModel: ObservableObject {
    @Published private(set) var state: WatchTrainingState = .notTraining
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var markers: [Date] = []

    private let now: () -> Date
    private let idFactory: () -> UUID

    var buttonTitle: String {
        switch state {
        case .notTraining:
            "长按开始"
        case .training:
            "双击打点 / 长按结束"
        }
    }

    var buttonColor: Color {
        switch state {
        case .notTraining:
            .green
        case .training:
            .red
        }
    }

    var markerCount: Int {
        state == .training ? markers.count : 0
    }

    var markerCountText: String {
        "打点数: \(markerCount)"
    }

    init(
        now: @escaping () -> Date = Date.init,
        idFactory: @escaping () -> UUID = UUID.init,
    ) {
        self.now = now
        self.idFactory = idFactory
    }

    @discardableResult
    func handleLongPress() -> TrainingSessionSyncPayload? {
        switch state {
        case .notTraining:
            startedAt = now()
            endedAt = nil
            markers = []
            state = .training
            return nil
        case .training:
            let completedAt = now()
            endedAt = completedAt
            state = .notTraining
            return TrainingSessionSyncPayload(
                id: idFactory(),
                startedAt: startedAt ?? completedAt,
                endedAt: completedAt,
                events: markers.map {
                    ShotMarkerEventSyncPayload(id: idFactory(), markedAt: $0)
                },
            )
        }
    }

    @discardableResult
    func handleDoubleTap() -> Bool {
        guard state == .training else {
            return false
        }

        markers.append(now())
        return true
    }
}

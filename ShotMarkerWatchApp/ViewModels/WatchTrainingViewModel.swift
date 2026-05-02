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

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func handleLongPress() {
        switch state {
        case .notTraining:
            startedAt = now()
            endedAt = nil
            markers = []
            state = .training
        case .training:
            endedAt = now()
            state = .notTraining
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

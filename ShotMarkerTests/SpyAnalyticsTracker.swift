@testable import ShotMarker
import Foundation

nonisolated final class SpyAnalyticsTracker: AnalyticsTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [AnalyticsEvent] = []

    var events: [AnalyticsEvent] {
        lock.withLock {
            storedEvents
        }
    }

    func track(_ event: AnalyticsEvent) {
        lock.withLock {
            storedEvents.append(event)
        }
    }
}

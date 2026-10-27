@testable import ShotMarker
import Foundation

nonisolated final class SpyAnalyticsTracker: AnalyticsTracking, @unchecked Sendable {
    struct Record: Sendable {
        let event: AnalyticsEvent
        let operationID: UUID?
        let stage: AnalyticsStage?
        let reason: AnalyticsReason?
    }
    private let lock = NSLock()
    private var storedRecords: [Record] = []
    var records: [Record] { lock.withLock { storedRecords } }
    var events: [AnalyticsEvent] { records.map(\.event) }
    func track(_ event: AnalyticsEvent) {
        lock.withLock { storedRecords.append(Record(event: event, operationID: nil, stage: nil, reason: nil)) }
    }
    func track(_ event: AnalyticsEvent, operationID: UUID, stage: AnalyticsStage, reason: AnalyticsReason?) {
        lock.withLock { storedRecords.append(Record(event: event, operationID: operationID, stage: stage, reason: reason)) }
    }
}

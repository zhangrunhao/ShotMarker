import Foundation

nonisolated enum AnalyticsEvent: String, CaseIterable, Sendable {
    case appLaunch = "app_launch"
    case trainingSyncSucceeded = "training_sync_succeeded"
    case highlightGenerateSucceeded = "highlight_generate_succeeded"
    case highlightSaveSucceeded = "highlight_save_succeeded"
}

nonisolated protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
}

nonisolated struct NoopAnalyticsTracker: AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {}
}

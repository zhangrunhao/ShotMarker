import SwiftUI

@main
struct ShotMarkerWatchApp: App {
    private let syncService: WatchTrainingSyncService

    @MainActor
    init() {
        syncService = WatchTrainingSyncService()
    }

    var body: some Scene {
        WindowGroup {
            WatchTrainingView(syncService: syncService)
        }
    }
}

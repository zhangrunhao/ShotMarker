//
//  ShotMarkerApp.swift
//  ShotMarker
//
//  Created by runhao zhang on 2026/5/1.
//

import SwiftUI

@main
struct ShotMarkerApp: App {
    private let store: TrainingSessionStore
    private let syncService: PhoneWatchSyncService

    @MainActor
    init() {
        #if DEBUG
            let store = TrainingSessionStore(seedSessions: TrainingSession.previewSessions)
        #else
            let store = TrainingSessionStore()
        #endif
        let syncService = PhoneWatchSyncService(importer: TrainingSessionImporter(store: store))

        self.store = store
        self.syncService = syncService
        syncService.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, syncService: syncService)
        }
    }
}

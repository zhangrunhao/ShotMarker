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
    private let logger: AppLogging
    private let logExportService: AppLogExportService

    @MainActor
    init() {
        #if DEBUG
            let store = TrainingSessionStore(seedSessions: TrainingSession.previewSessions)
        #else
            let store = TrainingSessionStore()
        #endif
        let logStore = AppLogStore.shared
        let logger = AppLogger.shared
        let syncService = PhoneWatchSyncService(
            importer: TrainingSessionImporter(store: store),
            logger: logger,
        )
        let logExportService = AppLogExportService(
            store: logStore,
            diagnosticsSnapshotProvider: syncService.diagnosticsSnapshot,
        )

        self.store = store
        self.syncService = syncService
        self.logger = logger
        self.logExportService = logExportService
        logger.info(
            "app.launch",
            category: .app,
            message: "应用启动",
        )
        syncService.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                syncService: syncService,
                logger: logger,
                logExportService: logExportService,
            )
        }
    }
}

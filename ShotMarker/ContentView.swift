//
//  ContentView.swift
//  ShotMarker
//
//  Created by runhao zhang on 2026/5/1.
//

import SwiftUI

struct ContentView: View {
    private let store: TrainingSessionStoreProtocol
    private let syncService: PhoneWatchSyncService?
    private let logger: AppLogging
    private let logExportService: AppLogExportService?

    @MainActor
    init(
        store: TrainingSessionStoreProtocol,
        syncService: PhoneWatchSyncService? = nil,
        logger: AppLogging = AppLogger.shared,
        logExportService: AppLogExportService? = nil,
    ) {
        self.store = store
        self.syncService = syncService
        self.logger = logger
        self.logExportService = logExportService
    }

    var body: some View {
        TrainingSessionListView(
            store: store,
            diagnosticsSnapshotProvider: syncService?.diagnosticsSnapshot,
            logger: logger,
            logExportService: logExportService,
        )
    }
}

#if DEBUG
    #Preview {
        ContentView(store: InMemoryTrainingSessionStore(sessions: TrainingSession.previewSessions))
    }
#endif

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
    #if os(iOS)
        private let highlightJobManager: HighlightJobManager?
    #endif

    @MainActor
    init(
        store: TrainingSessionStoreProtocol,
        syncService: PhoneWatchSyncService? = nil,
        logger: AppLogging = AppLogger.shared,
        logExportService: AppLogExportService? = nil,
        highlightJobManager: HighlightJobManager? = nil,
    ) {
        self.store = store
        self.syncService = syncService
        self.logger = logger
        self.logExportService = logExportService
        #if os(iOS)
            self.highlightJobManager = highlightJobManager
        #endif
    }

    var body: some View {
        TrainingSessionListView(
            store: store,
            diagnosticsSnapshotProvider: syncService?.diagnosticsSnapshot,
            logger: logger,
            logExportService: logExportService,
            highlightJobManager: highlightJobManager,
        )
    }
}

#if DEBUG
    #Preview {
        ContentView(store: InMemoryTrainingSessionStore(sessions: TrainingSession.previewSessions))
    }
#endif

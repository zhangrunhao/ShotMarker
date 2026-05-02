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

    @MainActor
    init(store: TrainingSessionStoreProtocol, syncService: PhoneWatchSyncService? = nil) {
        self.store = store
        self.syncService = syncService
    }

    var body: some View {
        TrainingSessionListView(
            store: store,
            diagnosticsSnapshotProvider: syncService?.diagnosticsSnapshot,
        )
    }
}

#Preview {
    ContentView(store: InMemoryTrainingSessionStore(sessions: TrainingSession.previewSessions))
}

//
//  ContentView.swift
//  ShotMarker
//
//  Created by runhao zhang on 2026/5/1.
//

import SwiftUI

struct ContentView: View {
    private let store: TrainingSessionStoreProtocol

    @MainActor
    init(store: TrainingSessionStoreProtocol) {
        self.store = store
    }

    var body: some View {
        TrainingSessionListView(store: store)
    }
}

#Preview {
    ContentView(store: InMemoryTrainingSessionStore(sessions: TrainingSession.previewSessions))
}

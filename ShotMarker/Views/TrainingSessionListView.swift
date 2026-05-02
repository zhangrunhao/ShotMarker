import SwiftUI

struct TrainingSessionListView: View {
    @StateObject private var viewModel: TrainingSessionListViewModel
    private let diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)?

    @MainActor
    init(
        store: TrainingSessionStoreProtocol,
        diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)? = nil,
    ) {
        self.diagnosticsSnapshotProvider = diagnosticsSnapshotProvider
        _viewModel = StateObject(wrappedValue: TrainingSessionListViewModel(store: store))
    }

    @MainActor
    init(
        viewModel: TrainingSessionListViewModel,
        diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)? = nil,
    ) {
        self.diagnosticsSnapshotProvider = diagnosticsSnapshotProvider
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView("无法加载训练记录", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if viewModel.isEmpty {
                    ContentUnavailableView("暂无训练记录", systemImage: "applewatch", description: Text("结束一次手表训练后，训练记录会显示在这里。"))
                } else {
                    List(viewModel.rows) { row in
                        TrainingSessionRow(row: row)
                    }
                }
            }
            .navigationTitle("训练记录")
            .task {
                viewModel.load()
            }
            .toolbar {
                if let diagnosticsSnapshotProvider {
                    NavigationLink {
                        PhoneWatchSyncDiagnosticsView(snapshotProvider: diagnosticsSnapshotProvider)
                    } label: {
                        Image(systemName: "wave.3.right.circle")
                    }
                    .accessibilityLabel("同步诊断")
                }
            }
        }
    }
}

#Preview {
    TrainingSessionListView(
        viewModel: TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: TrainingSession.previewSessions),
        ),
    )
}

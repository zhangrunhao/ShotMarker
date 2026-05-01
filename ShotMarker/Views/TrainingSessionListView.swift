import SwiftUI

struct TrainingSessionListView: View {
    @StateObject private var viewModel: TrainingSessionListViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: TrainingSessionListViewModel(store: TrainingSessionStore()))
    }

    @MainActor
    init(viewModel: TrainingSessionListViewModel) {
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
        }
    }
}

#Preview {
    TrainingSessionListView(
        viewModel: TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: TrainingSession.previewSessions)
        )
    )
}

import SwiftUI

struct TimestampFileListView: View {
    @StateObject private var viewModel: TimestampListViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: TimestampListViewModel(store: TimestampFileStore()))
    }

    @MainActor
    init(viewModel: TimestampListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView("无法加载训练记录", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if viewModel.isEmpty {
                    ContentUnavailableView("暂无训练记录", systemImage: "applewatch", description: Text("结束一次手表训练后，时间戳文件会显示在这里。"))
                } else {
                    List(viewModel.rows) { row in
                        TimestampFileRow(row: row)
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
    TimestampFileListView(
        viewModel: TimestampListViewModel(
            store: InMemoryTimestampFileStore(files: TimestampFile.previewFiles)
        )
    )
}

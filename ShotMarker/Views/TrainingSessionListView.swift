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
            ZStack(alignment: .bottomTrailing) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                #if DEBUG && os(iOS)
                    if !viewModel.canMergeSelectedSessions {
                        VideoClipTestButton()
                            .padding(.trailing, 20)
                            .padding(.bottom, 24)
                    }
                #endif
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.canMergeSelectedSessions {
                    mergeActionBar
                }
            }
            .navigationTitle("训练记录")
            .task {
                viewModel.load()
            }
            .toolbar {
                if viewModel.isSelectionMode {
                    Button("取消") {
                        viewModel.clearSelection()
                    }
                } else if let diagnosticsSnapshotProvider {
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

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView("无法加载训练记录", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if viewModel.isEmpty {
            ContentUnavailableView("暂无训练记录", systemImage: "applewatch", description: Text("结束一次手表训练后，训练记录会显示在这里。"))
        } else {
            List(viewModel.rows) { row in
                if viewModel.isSelectionMode {
                    TrainingSessionRow(
                        row: row,
                        isSelectionMode: true,
                        isSelected: viewModel.isSelected(row.id),
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleSelection(for: row.id)
                    }
                    .listRowBackground(viewModel.isSelected(row.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                } else {
                    NavigationLink {
                        destination(for: row)
                    } label: {
                        TrainingSessionRow(row: row)
                    }
                    .simultaneousGesture(
                        LongPressGesture().onEnded { _ in
                            viewModel.beginSelection(with: row.id)
                        },
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for row: TrainingSessionRowViewData) -> some View {
        #if os(iOS)
            if let session = viewModel.session(for: row.id) {
                TrainingSessionHighlightView(session: session)
            } else {
                ContentUnavailableView("无法加载训练记录", systemImage: "exclamationmark.triangle")
            }
        #else
            ContentUnavailableView("无法生成集锦", systemImage: "video.slash")
        #endif
    }

    private var mergeActionBar: some View {
        Button {
            viewModel.mergeSelectedSessions()
        } label: {
            Text("合并")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

#if DEBUG
    #Preview {
        TrainingSessionListView(
            viewModel: TrainingSessionListViewModel(
                store: InMemoryTrainingSessionStore(sessions: TrainingSession.previewSessions),
            ),
        )
    }
#endif

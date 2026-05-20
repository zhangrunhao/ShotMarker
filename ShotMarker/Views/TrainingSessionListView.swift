import SwiftUI

struct TrainingSessionListView: View {
    @StateObject private var viewModel: TrainingSessionListViewModel
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var logExportErrorMessage: String?
    private let diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)?
    private let logger: AppLogging
    private let logExportService: AppLogExportService?

    @MainActor
    init(
        store: TrainingSessionStoreProtocol,
        diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)? = nil,
        logger: AppLogging = AppLogger.shared,
        logExportService: AppLogExportService? = nil,
    ) {
        self.diagnosticsSnapshotProvider = diagnosticsSnapshotProvider
        self.logger = logger
        self.logExportService = logExportService
        _viewModel = StateObject(wrappedValue: TrainingSessionListViewModel(store: store, logger: logger))
    }

    @MainActor
    init(
        viewModel: TrainingSessionListViewModel,
        diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)? = nil,
        logger: AppLogging = AppLogger.shared,
        logExportService: AppLogExportService? = nil,
    ) {
        self.diagnosticsSnapshotProvider = diagnosticsSnapshotProvider
        self.logger = logger
        self.logExportService = logExportService
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                } else if logExportService != nil {
                    Button {
                        Task { await exportLogs() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("导出日志")
                    .disabled(isExportingLogs)
                }
            }
            #if os(iOS)
                .sheet(isPresented: exportedLogSheetBinding) {
                    if let exportedLogURL {
                        AppLogShareSheet(fileURL: exportedLogURL)
                    }
                }
            #endif
            .alert("导出日志失败", isPresented: logExportErrorBinding) {
                Button("好", role: .cancel) {
                    logExportErrorMessage = nil
                }
            } message: {
                Text(logExportErrorMessage ?? "未知错误")
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

    private var exportedLogSheetBinding: Binding<Bool> {
        Binding(
            get: { exportedLogURL != nil },
            set: { isPresented in
                if !isPresented {
                    exportedLogURL = nil
                }
            },
        )
    }

    private var logExportErrorBinding: Binding<Bool> {
        Binding(
            get: { logExportErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    logExportErrorMessage = nil
                }
            },
        )
    }

    @MainActor
    private func exportLogs() async {
        guard let logExportService else {
            return
        }

        isExportingLogs = true
        logger.info(
            "diagnostics.export.started",
            category: .diagnostics,
            message: "开始导出诊断日志",
        )

        do {
            exportedLogURL = try await logExportService.export()
        } catch {
            logExportErrorMessage = (error as NSError).localizedDescription
            logger.error(
                "diagnostics.export.failed",
                category: .diagnostics,
                message: "诊断日志导出失败",
                error: error,
            )
        }

        isExportingLogs = false
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

import SwiftUI
import UniformTypeIdentifiers

struct TrainingSessionListView: View {
    @StateObject private var viewModel: TrainingSessionListViewModel
    @State private var isImportingTrainingSessions = false
    @State private var isExportingTrainingSessions = false
    @State private var trainingSessionExportDocument: TrainingSessionJSONDocument?
    @State private var trainingSessionExportCount = 0
    @State private var trainingSessionTransferAlert: TrainingSessionTransferAlert?
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            viewModel.clearSelection()
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            prepareSelectedTrainingSessionExport()
                        } label: {
                            Label("导出记录", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isExportingTrainingSessions)
                    }
                } else {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            isImportingTrainingSessions = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("导入训练记录")

                        if logExportService != nil {
                            Button {
                                Task { await exportLogs() }
                            } label: {
                                Image(systemName: "doc.text")
                            }
                            .accessibilityLabel("导出日志")
                            .disabled(isExportingLogs)
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $isImportingTrainingSessions,
                allowedContentTypes: [.json],
            ) { result in
                handleTrainingSessionImport(result)
            }
            .fileExporter(
                isPresented: $isExportingTrainingSessions,
                document: trainingSessionExportDocument,
                contentType: .json,
                defaultFilename: "山药蛋-TrainingSessions.json",
            ) { result in
                handleTrainingSessionExport(result)
            }
            .alert(trainingSessionTransferAlert?.title ?? "", isPresented: trainingSessionTransferAlertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(trainingSessionTransferAlert?.message ?? "")
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

    private var trainingSessionTransferAlertBinding: Binding<Bool> {
        Binding(
            get: { trainingSessionTransferAlert != nil },
            set: { isPresented in
                if !isPresented {
                    trainingSessionTransferAlert = nil
                }
            },
        )
    }

    @MainActor
    private func prepareSelectedTrainingSessionExport() {
        let selectedCount = viewModel.selectedSessionsForExport().count
        logger.info(
            "training.sessions.export.started",
            category: .training,
            message: "开始导出训练记录",
            context: ["selectedTrainingSessionCount": "\(selectedCount)"],
        )

        do {
            let data = try viewModel.exportSelectedSessionsData()
            trainingSessionExportDocument = TrainingSessionJSONDocument(data: data)
            trainingSessionExportCount = selectedCount
            isExportingTrainingSessions = true
        } catch {
            logger.error(
                "training.sessions.export.failed",
                category: .training,
                message: "训练记录导出失败",
                error: error,
                context: ["selectedTrainingSessionCount": "\(selectedCount)"],
            )
            trainingSessionTransferAlert = .exportFailed(error)
        }
    }

    @MainActor
    private func handleTrainingSessionExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            logger.info(
                "training.sessions.export.succeeded",
                category: .training,
                message: "训练记录导出成功",
                context: ["exportedTrainingSessionCount": "\(trainingSessionExportCount)"],
            )
            trainingSessionTransferAlert = .exportSucceeded(count: trainingSessionExportCount)
            trainingSessionExportDocument = nil
            trainingSessionExportCount = 0
            viewModel.clearSelection()
        case .failure(let error):
            guard !(error is CancellationError) else {
                trainingSessionExportDocument = nil
                trainingSessionExportCount = 0
                return
            }

            logger.error(
                "training.sessions.export.failed",
                category: .training,
                message: "训练记录导出失败",
                error: error,
                context: ["exportedTrainingSessionCount": "\(trainingSessionExportCount)"],
            )
            trainingSessionTransferAlert = .exportFailed(error)
            trainingSessionExportDocument = nil
            trainingSessionExportCount = 0
        }
    }

    @MainActor
    private func handleTrainingSessionImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let fileURL):
            logger.info(
                "training.sessions.import.started",
                category: .training,
                message: "开始导入训练记录",
            )

            do {
                let importResult = try viewModel.importTrainingSessions(from: fileURL)
                logger.info(
                    "training.sessions.import.succeeded",
                    category: .training,
                    message: "训练记录导入成功",
                    context: [
                        "importedTrainingSessionCount": "\(importResult.importedCount)",
                        "insertedTrainingSessionCount": "\(importResult.insertedCount)",
                        "replacedTrainingSessionCount": "\(importResult.replacedCount)",
                    ],
                )
                trainingSessionTransferAlert = .importSucceeded(importResult)
            } catch {
                logger.error(
                    "training.sessions.import.failed",
                    category: .training,
                    message: "训练记录导入失败",
                    error: error,
                )
                trainingSessionTransferAlert = .importFailed(error)
            }
        case .failure(let error):
            guard !(error is CancellationError) else {
                return
            }

            logger.error(
                "training.sessions.import.failed",
                category: .training,
                message: "训练记录导入失败",
                error: error,
            )
            trainingSessionTransferAlert = .importFailed(error)
        }
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

private struct TrainingSessionJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct TrainingSessionTransferAlert {
    let title: String
    let message: String

    static func importSucceeded(_ result: TrainingSessionJSONImportResult) -> TrainingSessionTransferAlert {
        let message = "已导入 \(result.importedCount) 条训练记录，"
            + "其中新增 \(result.insertedCount) 条，覆盖 \(result.replacedCount) 条。"

        return TrainingSessionTransferAlert(
            title: "导入完成",
            message: message,
        )
    }

    static func importFailed(_ error: Error) -> TrainingSessionTransferAlert {
        TrainingSessionTransferAlert(
            title: "导入失败",
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
        )
    }

    static func exportSucceeded(count: Int) -> TrainingSessionTransferAlert {
        TrainingSessionTransferAlert(
            title: "导出完成",
            message: "已导出 \(count) 条训练记录。",
        )
    }

    static func exportFailed(_ error: Error) -> TrainingSessionTransferAlert {
        TrainingSessionTransferAlert(
            title: "导出失败",
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
        )
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

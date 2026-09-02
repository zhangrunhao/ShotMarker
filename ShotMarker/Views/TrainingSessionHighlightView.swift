#if os(iOS)
    import Foundation
    import PhotosUI
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    struct TrainingSessionHighlightView: View {
        let session: TrainingSession
        @Environment(\.dismiss) private var dismiss

        private let logger: AppLogging
        private let highlightJobManager: HighlightJobManager?
        private let videoLoadingService: TrainingVideoLoadingService<PhotosPickerItem>
        private let photoLibraryAssetProvider: PhotoLibraryVideoAssetProvider
        private let temporaryFileStore: TrainingVideoTemporaryFileStore

        @State private var selectedItems: [PhotosPickerItem] = []
        @State private var selectedVideos: [SelectedTrainingVideo] = []
        @State private var isLoadingVideos = false
        @State private var isCreatingHighlightJob = false
        @State private var clipSettings = ClipSettingsStore.shared.load()
        @State private var selectedVideoItems: [SelectedTrainingVideoSelectionItem] = []
        @State private var preparationConfirmationItemID: String?
        @State private var preparationTasks: [String: Task<Void, Never>] = [:]
        @State private var preparationRunIDs: [String: UUID] = [:]
        @State private var alert: HighlightFlowAlert?
        @State private var isExportingTrainingSession = false
        @State private var trainingSessionExportDocument: TrainingSessionJSONDocument?

        init(
            session: TrainingSession,
            logger: AppLogging = AppLogger.shared,
            highlightJobManager: HighlightJobManager? = nil,
        ) {
            self.session = session
            self.logger = logger
            self.highlightJobManager = highlightJobManager

            let photoLibraryAssetProvider = PhotoLibraryVideoAssetProvider()
            let temporaryFileStore = TrainingVideoTemporaryFileStore()
            self.photoLibraryAssetProvider = photoLibraryAssetProvider
            self.temporaryFileStore = temporaryFileStore
            videoLoadingService = TrainingVideoLoadingService.live(
                photoLibraryAssetProvider: photoLibraryAssetProvider,
                temporaryFileStore: temporaryFileStore,
            )
        }

        private var plan: HighlightClipPlan {
            VideoClipSegmentPlanner.highlightPlan(
                for: session,
                videos: selectedVideos,
                clipSettings: clipSettings,
            )
        }

        var body: some View {
            List {
                trainingSummarySection
                clipSettingsSection
                videoPickerSection
                selectedVideoItemsSection
                markerLabelSettingsSection
                coverageAndGenerationSections
            }
            .navigationTitle("生成集锦")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        prepareTrainingSessionExport()
                    } label: {
                        Label("导出记录", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isCreatingHighlightJob || isExportingTrainingSession)
                }
            }
            .fileExporter(
                isPresented: $isExportingTrainingSession,
                document: trainingSessionExportDocument,
                contentType: .json,
                defaultFilename: "ShotMarker-TrainingSession-\(session.id.uuidString).json",
            ) { result in
                handleTrainingSessionExport(result)
            }
            .onChange(of: selectedItems) { _, newItems in
                Task {
                    await loadSelectedVideos(from: newItems)
                }
            }
            .onAppear {
                logHighlightViewOpened()
            }
            .onChange(of: selectedVideos) { _, _ in
                logPlanUpdated()
            }
            .onChange(of: clipSettings) { _, newSettings in
                ClipSettingsStore.shared.save(newSettings)
                logPlanUpdated()
            }
            .alert(alert?.title ?? "", isPresented: isShowingAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alert?.message ?? "")
            }
            .alert("下载或准备视频？", isPresented: isShowingPreparationConfirmation) {
                Button("取消", role: .cancel) {}
                Button("开始") {
                    startPreparingConfirmedVideo()
                }
            } message: {
                Text("可能需要从 iCloud 下载原视频，过程中可能消耗流量。")
            }
            .onDisappear {
                cancelPreparationTasks()
                cleanupTemporaryVideos()
            }
        }

        private var trainingRangeText: String {
            let start = session.startedAt.formatted(.dateTime.month().day().hour().minute())
            let end = session.endedAt.formatted(.dateTime.month().day().hour().minute())
            return "\(start) -> \(end)"
        }

        private var isShowingAlert: Binding<Bool> {
            Binding(
                get: { alert != nil },
                set: { isPresented in
                    if !isPresented {
                        alert = nil
                    }
                },
            )
        }

        private var isShowingPreparationConfirmation: Binding<Bool> {
            Binding(
                get: { preparationConfirmationItemID != nil },
                set: { isPresented in
                    if !isPresented {
                        preparationConfirmationItemID = nil
                    }
                },
            )
        }

        private var trainingSummarySection: some View {
            Section("训练") {
                LabeledContent("时间", value: trainingRangeText)
                LabeledContent("打点", value: "\(session.markerCount) 个")
            }
        }

        private var clipSettingsSection: some View {
            Section("剪辑范围") {
                Stepper(value: $clipSettings.secondsBeforeMarker, in: 0 ... 20, step: 1) {
                    LabeledContent("打点前", value: "\(Int(clipSettings.secondsBeforeMarker)) 秒")
                }

                Stepper(value: $clipSettings.secondsAfterMarker, in: 1 ... 20, step: 1) {
                    LabeledContent("打点后", value: "\(Int(clipSettings.secondsAfterMarker)) 秒")
                }
            }
            .disabled(isCreatingHighlightJob)
        }

        private var videoPickerSection: some View {
            Section {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 20,
                    matching: .videos,
                    photoLibrary: .shared(),
                ) {
                    Label(selectedVideoItems.isEmpty ? "选择视频" : "继续选择视频", systemImage: "video.badge.plus")
                }
                .disabled(isLoadingVideos || isCreatingHighlightJob)

                if isLoadingVideos {
                    ProgressView("读取视频")
                }
            }
        }

        @ViewBuilder
        private var coverageAndGenerationSections: some View {
            if !selectedVideos.isEmpty {
                coverageResultSection
                generateHighlightSection
            }
        }

        private var coverageResultSection: some View {
            Section("覆盖结果") {
                LabeledContent("已选择", value: "\(plan.selectedVideoCount) 个视频")
                LabeledContent("可剪辑", value: "\(plan.matchedMarkerCount) / \(plan.totalMarkerCount) 个打点")

                if plan.unmatchedMarkerCount > 0 {
                    Text("\(plan.unmatchedMarkerCount) 个打点不在所选视频范围内，生成时会跳过。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !plan.canGenerate {
                    Text("所选视频没有覆盖任何打点。请确认视频是否对应这次训练。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private var generateHighlightSection: some View {
            Section {
                Button {
                    Task {
                        await createHighlightJob()
                    }
                } label: {
                    HStack {
                        if isCreatingHighlightJob {
                            ProgressView()
                        }

                        Text(isCreatingHighlightJob ? "创建中" : "生成集锦")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!plan.canGenerate || isLoadingVideos || isCreatingHighlightJob)
            }
        }

        @ViewBuilder
        private var selectedVideoItemsSection: some View {
            if !selectedVideoItems.isEmpty {
                Section("已选视频") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(selectedVideoItems.rows(maximumItemsPerRow: 2).enumerated()), id: \.offset) { row in
                            HStack(spacing: 12) {
                                ForEach(row.element) { item in
                                    selectedVideoItemCard(item)
                                }

                                if row.element.count < 2 {
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }

        @ViewBuilder
        private var markerLabelSettingsSection: some View {
            if let firstSelectedItem = selectedVideoItems.first {
                Section("片段序数") {
                    MarkerLabelSettingsView(
                        thumbnailData: firstSelectedItem.thumbnailData,
                        previewLabel: plan.segments.first?.markerLabel ?? "1/1",
                        isDisabled: isCreatingHighlightJob,
                        style: $clipSettings.markerLabelStyle,
                    )
                }
            }
        }

        @MainActor
        private func prepareTrainingSessionExport() {
            logger.info(
                "training.session.export.started",
                category: .training,
                message: "开始导出单次训练记录",
                context: highlightContext(),
            )

            do {
                let data = try TrainingSessionJSONTransferService(
                    store: InMemoryTrainingSessionStore(sessions: []),
                )
                .exportData(for: [session])
                trainingSessionExportDocument = TrainingSessionJSONDocument(data: data)
                isExportingTrainingSession = true
            } catch {
                logger.error(
                    "training.session.export.failed",
                    category: .training,
                    message: "单次训练记录导出失败",
                    error: error,
                    context: highlightContext(),
                )
                alert = HighlightFlowAlert(
                    title: "导出失败",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                )
            }
        }

        @MainActor
        private func handleTrainingSessionExport(_ result: Result<URL, Error>) {
            switch result {
            case .success:
                logger.info(
                    "training.session.export.succeeded",
                    category: .training,
                    message: "单次训练记录导出成功",
                    context: highlightContext(),
                )
                alert = HighlightFlowAlert(title: "导出完成", message: "已导出这次训练记录。")
                trainingSessionExportDocument = nil
            case let .failure(error):
                guard !(error is CancellationError) else {
                    trainingSessionExportDocument = nil
                    return
                }

                logger.error(
                    "training.session.export.failed",
                    category: .training,
                    message: "单次训练记录导出失败",
                    error: error,
                    context: highlightContext(),
                )
                alert = HighlightFlowAlert(
                    title: "导出失败",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                )
                trainingSessionExportDocument = nil
            }
        }

        @ViewBuilder
        private func selectedVideoItemCard(_ item: SelectedTrainingVideoSelectionItem) -> some View {
            if item.canControlPreparation {
                Button {
                    handlePreparationControlTapped(for: item)
                } label: {
                    selectedVideoItemCardContent(item)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingVideos || isCreatingHighlightJob)
            } else {
                selectedVideoItemCardContent(item)
            }
        }

        private func selectedVideoItemCardContent(_ item: SelectedTrainingVideoSelectionItem) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    selectedVideoThumbnail(for: item)

                    if item.isAvailable {
                        VStack {
                            HStack {
                                Label("可用", systemImage: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(.green.opacity(0.9), in: Capsule())
                                    .foregroundStyle(.white)

                                Spacer()
                            }

                            Spacer()
                        }
                        .padding(6)
                    } else if item.isPreparing {
                        Color.black.opacity(0.62)

                        VStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)

                            Text(item.preparationProgressText ?? "0%")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    } else if item.isPreparationPaused {
                        Color.black.opacity(0.62)

                        VStack(spacing: 6) {
                            Image(systemName: "pause.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white)

                            Text(item.statusText)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    } else {
                        Color.black.opacity(0.58)

                        Text(item.statusText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(width: 156, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 156, alignment: .leading)
        }

        @ViewBuilder
        private func selectedVideoThumbnail(for item: SelectedTrainingVideoSelectionItem) -> some View {
            if let thumbnailData = item.thumbnailData,
               let image = UIImage(data: thumbnailData)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 156, height: 88)
                    .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(.secondary.opacity(0.16))

                    Image(systemName: "video")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 156, height: 88)
            }
        }

        private func logHighlightViewOpened() {
            logger.info(
                "highlight.view.opened",
                category: .video,
                message: "打开集锦生成页面",
                context: highlightContext(),
            )
        }

        private func logPlanUpdated() {
            logger.info(
                "highlight.plan.updated",
                category: .video,
                message: "集锦剪辑计划更新",
                context: highlightPlanContext(plan),
            )
        }

        @MainActor
        private func handlePreparationControlTapped(for item: SelectedTrainingVideoSelectionItem) {
            if item.isPreparing {
                pausePreparingVideo(withID: item.id)
                return
            }

            if item.canResumePreparation {
                startPreparingVideo(withID: item.id)
                return
            }

            if item.canPrepare {
                preparationConfirmationItemID = item.id
            }
        }

        @MainActor
        private func startPreparingConfirmedVideo() {
            guard let itemID = preparationConfirmationItemID else {
                return
            }

            preparationConfirmationItemID = nil
            startPreparingVideo(withID: itemID)
        }

        @MainActor
        private func startPreparingVideo(withID itemID: String) {
            guard preparationTasks[itemID] == nil else {
                return
            }

            let runID = UUID()
            preparationRunIDs[itemID] = runID

            let task = Task {
                await prepareSelectedVideoItem(withID: itemID, runID: runID)
            }
            preparationTasks[itemID] = task
        }

        @MainActor
        private func pausePreparingVideo(withID itemID: String) {
            guard let task = preparationTasks[itemID] else {
                return
            }

            task.cancel()
            preparationTasks[itemID] = nil
            preparationRunIDs[itemID] = nil

            guard let itemIndex = selectedVideoItems.firstIndex(where: { $0.id == itemID }) else {
                return
            }

            let item = selectedVideoItems[itemIndex]
            guard item.isPreparing else {
                return
            }

            selectedVideoItems[itemIndex] = item.pausedPreparation()

            logger.info(
                "video.prepare.paused",
                category: .video,
                message: "已暂停准备所选视频",
                context: highlightContext(extra: ["videoID": itemID]),
            )
        }

        @MainActor
        private func cancelPreparationTasks(excluding retainedItemIDs: Set<String> = []) {
            for itemID in Array(preparationTasks.keys) where !retainedItemIDs.contains(itemID) {
                preparationTasks[itemID]?.cancel()
                preparationTasks[itemID] = nil
                preparationRunIDs[itemID] = nil
            }
        }

        @MainActor
        private func prepareSelectedVideoItem(withID itemID: String, runID: UUID) async {
            defer {
                if preparationRunIDs[itemID] == runID {
                    preparationTasks[itemID] = nil
                    preparationRunIDs[itemID] = nil
                }
            }

            guard let itemIndex = selectedVideoItems.firstIndex(where: { $0.id == itemID }) else {
                return
            }

            let item = selectedVideoItems[itemIndex]
            guard item.canPrepare || item.canResumePreparation, let video = item.video else {
                return
            }

            selectedVideoItems[itemIndex] = item.resumedPreparation()

            logger.info(
                "video.prepare.started",
                category: .video,
                message: "开始准备所选视频",
                context: highlightContext(extra: [
                    "videoID": video.id,
                ]),
            )

            do {
                let asset = try photoLibraryAssetProvider.photoAsset(with: video.id)
                _ = try await photoLibraryAssetProvider.requestAVAsset(
                    for: asset,
                    deliveryQuality: .high,
                    progressHandler: { progress in
                        Task { @MainActor in
                            updatePreparationProgress(for: itemID, runID: runID, progress: progress)
                        }
                    },
                )

                updatePreparationProgress(for: itemID, runID: runID, progress: 1)

                guard preparationRunIDs[itemID] == runID else {
                    return
                }
                guard let latestIndex = selectedVideoItems.firstIndex(where: { $0.id == itemID }),
                      let availableItem = selectedVideoItems[latestIndex].availableAfterPreparation()
                else {
                    return
                }

                selectedVideoItems[latestIndex] = availableItem
                selectedVideos = selectedVideoItems.availableVideos

                logger.info(
                    "video.prepare.succeeded",
                    category: .video,
                    message: "所选视频已准备完成",
                    context: highlightContext(extra: [
                        "videoID": video.id,
                    ]),
                )
            } catch {
                guard preparationRunIDs[itemID] == runID,
                      !(error is CancellationError)
                else {
                    return
                }

                guard let latestIndex = selectedVideoItems.firstIndex(where: { $0.id == itemID }) else {
                    return
                }

                selectedVideoItems[latestIndex] = .unavailable(
                    id: item.id,
                    title: item.title,
                    video: video,
                    reason: .notReady,
                    thumbnailData: item.thumbnailData,
                )
                selectedVideos = selectedVideoItems.availableVideos
                alert = HighlightFlowAlert(
                    title: "准备失败",
                    message: "视频暂时没有准备好。请确认网络可用后再试。",
                )

                logger.warning(
                    "video.prepare.failed",
                    category: .video,
                    message: "所选视频准备失败",
                    context: highlightContext(extra: [
                        "videoID": video.id,
                        "error": "\(error)",
                    ]),
                )
            }
        }

        @MainActor
        private func updatePreparationProgress(for itemID: String, runID: UUID, progress: Double) {
            guard preparationRunIDs[itemID] == runID else {
                return
            }

            guard let itemIndex = selectedVideoItems.firstIndex(where: { $0.id == itemID }) else {
                return
            }

            let item = selectedVideoItems[itemIndex]
            guard item.isPreparing else {
                return
            }

            selectedVideoItems[itemIndex] = item.preparing(progress: progress)
        }

        @MainActor
        private func loadSelectedVideos(from items: [PhotosPickerItem]) async {
            let retainedItemIDs = Set(items.compactMap(\.itemIdentifier))
            let retainedPreparationItems = selectedVideoItems
                .filter { retainedItemIDs.contains($0.id) && ($0.isPreparing || $0.isPreparationPaused) }
                .reduce(into: [String: SelectedTrainingVideoSelectionItem]()) { result, item in
                    result[item.id] = item
                }

            cancelPreparationTasks(excluding: retainedItemIDs)
            cleanupTemporaryVideos()
            selectedVideos = []
            selectedVideoItems = []

            guard !items.isEmpty else {
                return
            }

            logger.info(
                "video.selection.started",
                category: .video,
                message: "开始读取所选视频",
                context: highlightContext(extra: ["requestedItemCount": "\(items.count)"]),
            )
            isLoadingVideos = true
            defer {
                isLoadingVideos = false
            }

            var selectionItems: [SelectedTrainingVideoSelectionItem] = []

            for (index, item) in items.enumerated() {
                var selectionItem = await loadSelectedVideoItem(from: item, at: index)
                if let retainedItem = retainedPreparationItems[selectionItem.id],
                   selectionItem.unavailableReason == .notReady
                {
                    selectionItem = selectionItem.preparing(progress: retainedItem.preparationProgress ?? 0)
                    if retainedItem.isPreparationPaused {
                        selectionItem = selectionItem.pausedPreparation()
                    }
                }
                selectionItems.append(selectionItem)

                if let video = selectionItem.video {
                    logger.info(
                        "video.selection.item.loaded",
                        category: .video,
                        message: "已读取所选视频",
                        context: highlightContext(extra: [
                            "itemIndex": "\(index + 1)",
                            "loadedVideoCount": "\(selectionItems.availableVideos.count)",
                            "source": item.itemIdentifier == nil ? "pickerFile" : "photoLibrary",
                            "durationSeconds": Self.secondsString(video.duration),
                        ]),
                    )
                } else if let unavailableReason = selectionItem.unavailableReason {
                    logger.warning(
                        "video.selection.item.filtered",
                        category: .video,
                        message: "已忽略不可用视频",
                        context: highlightContext(extra: [
                            "itemIndex": "\(index + 1)",
                            "reason": unavailableReason.logReason,
                        ]),
                    )
                }
            }

            selectedVideoItems = selectionItems
            selectedVideos = selectionItems.availableVideos
            reportVideoSelectionResultsIfNeeded(selectionItems)
        }

        @MainActor
        private func createHighlightJob() async {
            let currentPlan = plan
            guard currentPlan.canGenerate else {
                return
            }

            guard let highlightJobManager else {
                alert = HighlightFlowAlert(title: "无法创建任务", message: "集锦任务管理器不可用。")
                return
            }

            logger.info(
                "highlight.job.create.started",
                category: .video,
                message: "开始创建集锦任务",
                context: highlightPlanContext(currentPlan, extra: [
                    "segmentCount": "\(currentPlan.segments.count)",
                    "secondsBeforeMarker": Self.secondsString(clipSettings.secondsBeforeMarker),
                    "secondsAfterMarker": Self.secondsString(clipSettings.secondsAfterMarker),
                ]),
            )
            isCreatingHighlightJob = true
            defer {
                isCreatingHighlightJob = false
            }

            do {
                let reviewDraft = HighlightClipReviewPlanner.makeDraft(
                    for: session,
                    videos: selectedVideos,
                    clipSettings: clipSettings,
                )
                let confirmedSegments = try HighlightClipReviewPlanner.makeSummary(
                    items: reviewDraft.items,
                    videos: selectedVideos,
                ).finalSegments
                _ = try await highlightJobManager.createJob(
                    session: session,
                    selectedVideos: selectedVideos,
                    clipSettings: clipSettings,
                    confirmedSegments: confirmedSegments,
                )
                cancelPreparationTasks()
                cleanupTemporaryVideos()
                selectedItems = []
                selectedVideos = []
                selectedVideoItems = []
                logger.info(
                    "highlight.job.create.succeeded",
                    category: .video,
                    message: "集锦任务创建成功",
                    context: highlightPlanContext(currentPlan),
                )
                dismiss()
            } catch {
                logger.error(
                    "highlight.job.create.failed",
                    category: .video,
                    message: "集锦任务创建失败",
                    error: error,
                    context: highlightPlanContext(currentPlan),
                )
                alert = HighlightFlowAlert(
                    title: "创建任务失败",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                )
            }
        }

        private func highlightContext(extra: [String: String] = [:]) -> [String: String] {
            var context = [
                "trainingSessionId": session.id.uuidString,
                "totalMarkerCount": "\(session.markerCount)",
            ]
            context.merge(extra) { _, newValue in newValue }
            return context
        }

        private func highlightPlanContext(
            _ plan: HighlightClipPlan,
            extra: [String: String] = [:],
        ) -> [String: String] {
            highlightContext(extra: [
                "selectedVideoCount": "\(plan.selectedVideoCount)",
                "matchedMarkerCount": "\(plan.matchedMarkerCount)",
                "unmatchedMarkerCount": "\(plan.unmatchedMarkerCount)",
                "segmentCount": "\(plan.segments.count)",
            ].merging(extra) { _, newValue in newValue })
        }

        @MainActor
        private func loadSelectedVideoItem(
            from item: PhotosPickerItem,
            at index: Int,
        ) async -> SelectedTrainingVideoSelectionItem {
            let title = "视频 \(index + 1)"
            let fallbackID = "selection-\(index + 1)"
            return await videoLoadingService.loadSelectionItem(
                from: item,
                title: title,
                fallbackID: fallbackID,
                session: session,
            )
        }

        private func reportVideoSelectionResultsIfNeeded(_ selectionItems: [SelectedTrainingVideoSelectionItem]) {
            let unavailableItems = selectionItems.filter { !$0.isAvailable }
            guard !unavailableItems.isEmpty else {
                return
            }

            let countByReason = Dictionary(grouping: unavailableItems.compactMap(\.unavailableReason)) { $0 }
                .mapValues(\.count)

            logger.info(
                "video.selection.filtered",
                category: .video,
                message: "已过滤不可用视频",
                context: highlightContext(extra: [
                    "requestedItemCount": "\(selectionItems.count)",
                    "retainedVideoCount": "\(selectionItems.availableVideos.count)",
                    "filteredVideoCount": "\(unavailableItems.count)",
                    "failedToLoadCount": "\(countByReason[.failedToLoad, default: 0])",
                    "missingRecordedStartAtCount": "\(countByReason[.missingRecordedStartAt, default: 0])",
                    "invalidDurationCount": "\(countByReason[.invalidDuration, default: 0])",
                    "notReadyCount": "\(countByReason[.notReady, default: 0])",
                    "noMarkerCoverageCount": "\(countByReason[.noMarkerCoverage, default: 0])",
                    "photoLibraryAccessDeniedCount": "\(countByReason[.photoLibraryAccessDenied, default: 0])",
                ]),
            )
        }

        private func cleanupTemporaryVideos() {
            temporaryFileStore.cleanupTemporaryVideos(selectedVideos)
        }

        private func cleanupTemporaryVideos(_ videos: [SelectedTrainingVideo]) {
            temporaryFileStore.cleanupTemporaryVideos(videos)
        }

        private nonisolated static func secondsString(_ value: TimeInterval) -> String {
            String(format: "%.3f", value)
        }
    }

    private struct HighlightFlowAlert {
        let title: String
        let message: String
    }

    #if DEBUG
        #Preview {
            NavigationStack {
                TrainingSessionHighlightView(session: TrainingSession.previewSessions[0])
            }
        }
    #endif
#endif

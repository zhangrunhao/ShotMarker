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
        private let reviewStore: any HighlightClipReviewStoring

        @State private var selectedItems: [PhotosPickerItem] = []
        @State private var selectedVideos: [SelectedTrainingVideo] = []
        @State private var isLoadingVideos = false
        @State private var isCreatingHighlightJob = false
        @State private var clipSettings = ClipSettingsStore.shared.load()
        @State private var isMarkerLabelSettingsExpanded = false
        @State private var selectedVideoItems: [SelectedTrainingVideoSelectionItem] = []
        @State private var preparationConfirmationItemID: String?
        @State private var preparationTasks: [String: Task<Void, Never>] = [:]
        @State private var preparationRunIDs: [String: UUID] = [:]
        @State private var alert: HighlightFlowAlert?
        @State private var reviewViewModel: HighlightClipReviewViewModel?
        @State private var isReviewPresented = false
        @State private var isPreparingReview = false
        @State private var reviewPreparationRevision = UUID()
        @State private var isExportingTrainingSession = false
        @State private var trainingSessionExportDocument: TrainingSessionJSONDocument?

        init(
            session: TrainingSession,
            logger: AppLogging = AppLogger.shared,
            highlightJobManager: HighlightJobManager? = nil,
            reviewStore: any HighlightClipReviewStoring,
        ) {
            self.session = session
            self.logger = logger
            self.highlightJobManager = highlightJobManager
            self.reviewStore = reviewStore

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
            alertedFlowView
        }

        private var baseFlowView: some View {
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
                flowToolbarContent
            }
        }

        private var flowLifecycleView: some View {
            baseFlowView
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
            .navigationDestination(isPresented: $isReviewPresented) {
                reviewDestination
            }
        }

        private var alertedFlowView: some View {
            flowLifecycleView
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
                cleanupAfterWholeFlowDisappearsIfNeeded()
            }
        }

        @ToolbarContentBuilder
        private var flowToolbarContent: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    prepareTrainingSessionExport()
                } label: {
                    Label("导出记录", systemImage: "square.and.arrow.up")
                }
                .disabled(isCreatingHighlightJob || isExportingTrainingSession)
            }
        }

        @ViewBuilder
        private var reviewDestination: some View {
            if let reviewViewModel {
                HighlightClipReviewView(
                    viewModel: reviewViewModel,
                    makePlaybackController: {
                        HighlightClipPlaybackController { video in
                            try await reviewViewModel.mediaProvider.asset(for: video)
                        }
                    },
                    onRequestVideoReselection: {
                        isReviewPresented = false
                    },
                )
            } else {
                ContentUnavailableView(
                    "没有可审核片段",
                    systemImage: "film",
                    description: Text("返回后重新选择视频。"),
                )
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

        private var guardedSelectedItems: Binding<[PhotosPickerItem]> {
            Binding(
                get: { selectedItems },
                set: { proposedItems in
                    guard proposedItems != selectedItems else {
                        return
                    }
                    invalidateCurrentReview()
                    selectedItems = proposedItems
                },
            )
        }

        private var guardedSecondsBeforeMarker: Binding<TimeInterval> {
            guardedRangeSetting(
                currentValue: { clipSettings.secondsBeforeMarker },
                apply: { clipSettings.secondsBeforeMarker = $0 },
            )
        }

        private var guardedSecondsAfterMarker: Binding<TimeInterval> {
            guardedRangeSetting(
                currentValue: { clipSettings.secondsAfterMarker },
                apply: { clipSettings.secondsAfterMarker = $0 },
            )
        }

        private func guardedRangeSetting(
            currentValue: @escaping () -> TimeInterval,
            apply: @escaping (TimeInterval) -> Void,
        ) -> Binding<TimeInterval> {
            Binding(
                get: currentValue,
                set: { proposedValue in
                    guard proposedValue != currentValue() else {
                        return
                    }
                    invalidateCurrentReview()
                    apply(proposedValue)
                },
            )
        }

        @MainActor
        private func invalidateCurrentReview() {
            reviewPreparationRevision = UUID()
            reviewViewModel?.cancelMediaLoading()
            reviewViewModel = nil
            isReviewPresented = false
        }

        private var trainingSummarySection: some View {
            Section("训练") {
                LabeledContent("时间", value: trainingRangeText)
                LabeledContent("打点", value: "\(session.markerCount) 个")
            }
        }

        private var clipSettingsSection: some View {
            Section("剪辑范围") {
                Stepper(value: guardedSecondsBeforeMarker, in: 0 ... 20, step: 1) {
                    LabeledContent("打点前", value: "\(Int(clipSettings.secondsBeforeMarker)) 秒")
                }

                Stepper(value: guardedSecondsAfterMarker, in: 1 ... 20, step: 1) {
                    LabeledContent("打点后", value: "\(Int(clipSettings.secondsAfterMarker)) 秒")
                }
            }
            .disabled(isCreatingHighlightJob)
        }

        private var videoPickerSection: some View {
            Section {
                PhotosPicker(
                    selection: guardedSelectedItems,
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
                        await prepareReview()
                    }
                } label: {
                    HStack {
                        if isPreparingReview {
                            ProgressView()
                        }

                        Text(isPreparingReview ? "正在准备审核…" : "下一步：审核片段")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !plan.canGenerate
                        || isLoadingVideos
                        || isCreatingHighlightJob
                        || isPreparingReview,
                )
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
                    DisclosureGroup(
                        "样式调整",
                        isExpanded: $isMarkerLabelSettingsExpanded,
                    ) {
                        MarkerLabelSettingsView(
                            thumbnailData: firstSelectedItem.thumbnailData,
                            previewLabel: plan.segments.first?.markerLabel ?? "1/1",
                            isDisabled: isCreatingHighlightJob,
                            style: $clipSettings.markerLabelStyle,
                        )
                    }
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
                    reviewStore: reviewStore,
                    logger: logger,
                )
                .exportData(for: [session])
                trainingSessionExportDocument = TrainingSessionJSONDocument(data: data)
                isExportingTrainingSession = true
            } catch {
                logger.error(
                    "training.session.export.failed",
                    category: .training,
                    message: "单次训练记录导出失败",
                    error: nil,
                    context: highlightContext(extra: [
                        "errorCategory": "serializationFailed",
                    ]),
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
                    error: nil,
                    context: highlightContext(extra: [
                        "errorCategory": "fileExportFailed",
                    ]),
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
                context: videoPreparationContext(itemIndex: itemIndex, video: item.video),
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
                context: videoPreparationContext(itemIndex: itemIndex, video: video),
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
                    context: videoPreparationContext(itemIndex: latestIndex, video: video),
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
                    context: videoPreparationContext(
                        itemIndex: latestIndex,
                        video: video,
                        extra: [
                            "errorCategory": Self.videoPreparationErrorCategory(error),
                        ],
                    ),
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
            let previousSelectionVideos = selectedVideoItems.compactMap(\.video)
            let retainedItemIDs = Set(items.compactMap(\.itemIdentifier))
            let retainedPreparationItems = selectedVideoItems
                .filter { retainedItemIDs.contains($0.id) && ($0.isPreparing || $0.isPreparationPaused) }
                .reduce(into: [String: SelectedTrainingVideoSelectionItem]()) { result, item in
                    result[item.id] = item
                }

            cancelPreparationTasks(excluding: retainedItemIDs)
            cleanupTemporaryVideos(previousSelectionVideos)
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
        private func prepareReview() async {
            guard !isPreparingReview else {
                return
            }
            isPreparingReview = true
            defer {
                isPreparingReview = false
            }

            let videos = selectedVideoItems.availableVideos
            let settings = clipSettings.normalized
            guard !videos.isEmpty else {
                return
            }
            let preparationSnapshot = HighlightClipReviewPreparationSnapshot(
                videos: videos,
                clipSettings: settings,
                revision: reviewPreparationRevision,
            )

            do {
                let key = try HighlightClipReviewIdentityBuilder.combinationKey(
                    for: session,
                    videos: videos,
                )
                let loaded = try await reviewStore.loadRecord(for: key)
                guard preparationSnapshot.matches(
                    videos: selectedVideoItems.availableVideos,
                    clipSettings: clipSettings,
                    revision: reviewPreparationRevision,
                ) else {
                    return
                }
                let restoration = HighlightClipReviewPlanner.restoreDraft(
                    for: session,
                    videos: videos,
                    clipSettings: settings,
                    persistedRecord: loaded.record,
                )
                installReviewViewModel(
                    draft: restoration.draft,
                    key: key,
                    videos: videos,
                    settings: settings,
                    notice: reviewNotice(
                        storeNotice: loaded.notice,
                        discardedCount: restoration.discardedConfirmationCount,
                    ),
                    noticeCategory: Self.reviewNoticeCategory(
                        storeNotice: loaded.notice,
                        discardedCount: restoration.discardedConfirmationCount,
                    ),
                )
            } catch is CancellationError {
                return
            } catch {
                guard preparationSnapshot.matches(
                    videos: selectedVideoItems.availableVideos,
                    clipSettings: clipSettings,
                    revision: reviewPreparationRevision,
                ) else {
                    return
                }
                logger.error(
                    "highlight.review.prepare.failed",
                    category: .video,
                    message: "集锦片段审核准备失败",
                    error: nil,
                    context: highlightContext(extra: [
                        "selectedVideoCount": "\(videos.count)",
                        "errorCategory": Self.reviewPreparationErrorCategory(error),
                    ]),
                )
                alert = HighlightFlowAlert(
                    title: "无法准备片段审核",
                    message: Self.userFacingReviewPreparationMessage(for: error),
                )
            }
        }

        @MainActor
        private func installReviewViewModel(
            draft: HighlightClipReviewDraft,
            key: HighlightClipReviewCombinationKey,
            videos: [SelectedTrainingVideo],
            settings: ClipSettings,
            notice: String?,
            noticeCategory: String,
        ) {
            reviewViewModel?.cancelMediaLoading()
            guard !draft.items.isEmpty else {
                alert = HighlightFlowAlert(
                    title: "没有可审核片段",
                    message: "所选视频没有覆盖任何打点。请确认视频是否对应这次训练。",
                )
                return
            }

            let mediaProvider = HighlightClipReviewMediaProvider.live(
                photoLibraryAssetProvider: photoLibraryAssetProvider,
            )
            let settingsBinding = Binding<ClipSettings>(
                get: { self.clipSettings },
                set: { self.clipSettings = $0 },
            )
            let cleanupVideos = selectedVideoItems.compactMap(\.video)
            let defaultCardCount = draft.items.filter {
                $0.confirmationState == .defaultValue
            }.count
            let matchedMarkerCount = draft.matchedMarkerCount
            let manager = highlightJobManager
            let submissionVideos = videos
            let viewModel = HighlightClipReviewViewModel(
                draft: draft,
                videos: submissionVideos,
                clipSettings: settings,
                combinationKey: key,
                reviewStore: reviewStore,
                recoveryNoticeMessage: notice,
                mediaProvider: mediaProvider,
                submitSegments: { confirmedSegments in
                    guard let manager else {
                        throw HighlightReviewFlowError.jobManagerUnavailable
                    }

                    let includedCardCount = self.reviewViewModel?.items.filter(\.isIncluded).count ?? 0
                    let context = reviewContext(
                        defaultCardCount: defaultCardCount,
                        matchedMarkerCount: matchedMarkerCount,
                        includedCardCount: includedCardCount,
                        segments: confirmedSegments,
                    )
                    logger.info(
                        "highlight.review.submit.started",
                        category: .video,
                        message: "开始按审核结果创建集锦任务",
                        context: context,
                    )
                    isCreatingHighlightJob = true
                    defer {
                        isCreatingHighlightJob = false
                    }

                    do {
                        _ = try await manager.createJob(
                            session: session,
                            selectedVideos: submissionVideos,
                            clipSettings: settingsBinding.wrappedValue.normalized,
                            confirmedSegments: confirmedSegments,
                        )
                        logger.info(
                            "highlight.review.submit.succeeded",
                            category: .video,
                            message: "审核后的集锦任务创建成功",
                            context: context,
                        )
                    } catch {
                        logger.error(
                            "highlight.review.submit.failed",
                            category: .video,
                            message: "审核后的集锦任务创建失败",
                            error: nil,
                            context: context.merging([
                                "errorCategory": Self.jobCreationErrorCategory(error),
                            ]) { _, newValue in newValue },
                        )
                        throw error
                    }
                },
                onSubmissionSucceeded: {
                    completeSuccessfulHighlightCreation(cleanupVideos: cleanupVideos)
                },
            )
            reviewViewModel = viewModel
            logger.info(
                "highlight.review.prepared",
                category: .video,
                message: "集锦片段审核已准备",
                context: reviewContext(
                    defaultCardCount: defaultCardCount,
                    matchedMarkerCount: matchedMarkerCount,
                    includedCardCount: draft.items.filter(\.isIncluded).count,
                    segments: viewModel.summary.finalSegments,
                ).merging([
                    "selectedVideoCount": "\(videos.count)",
                    "recoveryNoticeCategory": noticeCategory,
                ]) { _, newValue in newValue },
            )
            isReviewPresented = true
        }

        @MainActor
        private func completeSuccessfulHighlightCreation(
            cleanupVideos: [SelectedTrainingVideo],
        ) {
            cancelPreparationTasks()
            reviewViewModel?.cancelMediaLoading()
            cleanupTemporaryVideos(cleanupVideos)
            selectedVideos = []
            selectedVideoItems = []
            selectedItems = []
            reviewViewModel = nil
            isReviewPresented = false

            Task { @MainActor in
                await Task.yield()
                dismiss()
            }
        }

        @MainActor
        private func cleanupAfterWholeFlowDisappearsIfNeeded() {
            guard !isReviewPresented else {
                return
            }

            cancelPreparationTasks()
            reviewViewModel?.cancelMediaLoading()
            cleanupTemporaryVideos(selectedVideoItems.compactMap(\.video))
        }

        private func highlightContext(extra: [String: String] = [:]) -> [String: String] {
            var context = [
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

        private func reviewContext(
            defaultCardCount: Int,
            matchedMarkerCount: Int,
            includedCardCount: Int,
            segments: [ConfirmedHighlightSegment],
        ) -> [String: String] {
            let includedMarkerCount = Set(segments.flatMap(\.markerIDs)).count
            return highlightContext(extra: [
                "defaultCardCount": "\(defaultCardCount)",
                "includedMarkerCount": "\(includedMarkerCount)",
                "excludedMarkerCount": "\(max(matchedMarkerCount - includedMarkerCount, 0))",
                "finalSegmentCount": "\(segments.count)",
                "totalDurationSeconds": String(
                    format: "%.1f",
                    segments.reduce(0) { $0 + $1.duration },
                ),
                "didMerge": segments.count < includedCardCount ? "true" : "false",
            ])
        }

        private func videoPreparationContext(
            itemIndex: Int,
            video: SelectedTrainingVideo?,
            extra: [String: String] = [:],
        ) -> [String: String] {
            highlightContext(extra: [
                "itemIndex": "\(itemIndex + 1)",
                "source": Self.sourceCategory(for: video),
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

        private func cleanupTemporaryVideos(_ videos: [SelectedTrainingVideo]) {
            temporaryFileStore.cleanupTemporaryVideos(videos)
        }

        private nonisolated static func sourceCategory(
            for video: SelectedTrainingVideo?,
        ) -> String {
            guard let video else {
                return "unknown"
            }
            if let url = URL(string: video.id), url.isFileURL {
                return "pickerFile"
            }
            return "photoLibrary"
        }

        private nonisolated static func videoPreparationErrorCategory(_ error: Error) -> String {
            error is CancellationError ? "cancelled" : "assetPreparationFailed"
        }

        private func reviewNotice(
            storeNotice: HighlightClipReviewStoreNotice?,
            discardedCount: Int,
        ) -> String? {
            var messages: [String] = []
            switch storeNotice {
            case .corruptDocumentRecovered:
                messages.append("已恢复损坏的片段确认文件，当前使用默认范围。")
            case .unsupportedSchemaVersion:
                messages.append("片段确认数据来自更新版本，当前使用默认范围；更新 App 后才能保存新的片段确认。")
            case nil:
                break
            }
            if discardedCount > 0 {
                messages.append("部分已保存片段无法恢复，已使用默认范围。")
            }
            return messages.isEmpty ? nil : messages.joined(separator: " ")
        }

        private nonisolated static func reviewNoticeCategory(
            storeNotice: HighlightClipReviewStoreNotice?,
            discardedCount: Int,
        ) -> String {
            let discarded = discardedCount > 0
            switch (storeNotice, discarded) {
            case (.corruptDocumentRecovered, true):
                return "corruptDocumentRecoveredAndDiscardedConfirmation"
            case (.corruptDocumentRecovered, false):
                return "corruptDocumentRecovered"
            case (.unsupportedSchemaVersion, true):
                return "unsupportedSchemaVersionAndDiscardedConfirmation"
            case (.unsupportedSchemaVersion, false):
                return "unsupportedSchemaVersion"
            case (nil, true):
                return "discardedConfirmation"
            case (nil, false):
                return "none"
            }
        }

        private nonisolated static func reviewPreparationErrorCategory(_ error: Error) -> String {
            if error is HighlightClipReviewIdentityError {
                return "identity"
            }
            if error is HighlightClipReviewStoreError {
                return "reviewStore"
            }
            if error is HighlightClipReviewPlanningError {
                return "planning"
            }
            return "reviewLoad"
        }

        private nonisolated static func userFacingReviewPreparationMessage(for error: Error) -> String {
            if error is HighlightClipReviewIdentityError
                || error is HighlightClipReviewStoreError
                || error is HighlightClipReviewPlanningError,
                let localizedError = error as? LocalizedError,
                let description = localizedError.errorDescription
            {
                return description
            }
            return "无法读取片段确认，请重试。"
        }

        private nonisolated static func jobCreationErrorCategory(_ error: Error) -> String {
            if error is CancellationError {
                return "cancelled"
            }
            if error is HighlightClipReviewPlanningError {
                return "validation"
            }
            if error is HighlightJobFileStoreError {
                return "fileStore"
            }
            if error is HighlightReviewFlowError {
                return "managerUnavailable"
            }
            return "taskCreation"
        }

        private nonisolated static func secondsString(_ value: TimeInterval) -> String {
            String(format: "%.3f", value)
        }
    }

    private struct HighlightFlowAlert {
        let title: String
        let message: String
    }

    private enum HighlightReviewFlowError: LocalizedError {
        case jobManagerUnavailable

        var errorDescription: String? {
            switch self {
            case .jobManagerUnavailable:
                "集锦任务管理器不可用。"
            }
        }
    }

    #if DEBUG
        #Preview {
            NavigationStack {
                TrainingSessionHighlightView(
                    session: TrainingSession.previewSessions[0],
                    reviewStore: InMemoryHighlightClipReviewStore(),
                )
            }
        }
    #endif
#endif

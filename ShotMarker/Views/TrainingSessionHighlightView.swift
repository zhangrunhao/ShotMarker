#if os(iOS)
    import AVFoundation
    import CoreTransferable
    import Foundation
    import Photos
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers

    struct TrainingSessionHighlightView: View {
        let session: TrainingSession
        private let logger: AppLogging
        private let editingService: VideoClipEditingService
        private let photoLibrarySaver: VideoClipPhotoLibrarySaver

        @State private var selectedItems: [PhotosPickerItem] = []
        @State private var selectedVideos: [SelectedTrainingVideo] = []
        @State private var isLoadingVideos = false
        @State private var isGenerating = false
        @State private var clipSettings = ClipSettingsStore.shared.load()
        @State private var generationProgress: HighlightClipGenerationProgress?
        @State private var alert: HighlightFlowAlert?

        init(session: TrainingSession, logger: AppLogging = AppLogger.shared) {
            self.session = session
            self.logger = logger
            editingService = VideoClipEditingService(logger: logger)
            photoLibrarySaver = VideoClipPhotoLibrarySaver(logger: logger)
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
                Section("训练") {
                    LabeledContent("时间", value: trainingRangeText)
                    LabeledContent("打点", value: "\(session.markerCount) 个")
                }

                Section("剪辑范围") {
                    Stepper(value: $clipSettings.secondsBeforeMarker, in: 0...20, step: 1) {
                        LabeledContent("打点前", value: "\(Int(clipSettings.secondsBeforeMarker)) 秒")
                    }

                    Stepper(value: $clipSettings.secondsAfterMarker, in: 1...20, step: 1) {
                        LabeledContent("打点后", value: "\(Int(clipSettings.secondsAfterMarker)) 秒")
                    }
                }
                .disabled(isGenerating)

                Section {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 20,
                        matching: .videos,
                        photoLibrary: .shared(),
                    ) {
                        Label(selectedVideos.isEmpty ? "选择视频" : "继续选择视频", systemImage: "video.badge.plus")
                    }
                    .disabled(isLoadingVideos || isGenerating)

                    if isLoadingVideos {
                        ProgressView("读取视频")
                    }
                }

                if !selectedVideos.isEmpty {
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

                    Section {
                        Button {
                            Task {
                                await generateHighlight()
                            }
                        } label: {
                            HStack {
                                if isGenerating {
                                    ProgressView()
                                }

                                Text(isGenerating ? "生成中" : "生成集锦")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!plan.canGenerate || isLoadingVideos || isGenerating)

                        if isGenerating, let generationProgress {
                            ProgressView(
                                value: Double(generationProgress.completedMarkerCount),
                                total: Double(generationProgress.totalMarkerCount),
                            ) {
                                Text("正在生成 \(generationProgress.completedMarkerCount)/\(generationProgress.totalMarkerCount)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("生成集锦")
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
            .onDisappear {
                if !isGenerating {
                    cleanupTemporaryVideos()
                }
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
        private func loadSelectedVideos(from items: [PhotosPickerItem]) async {
            cleanupTemporaryVideos()
            selectedVideos = []

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

            var videos: [SelectedTrainingVideo] = []

            do {
                for (index, item) in items.enumerated() {
                    let video = try await Self.loadSelectedVideo(from: item)
                    videos.append(video)
                    logger.info(
                        "video.selection.item.loaded",
                        category: .video,
                        message: "已读取所选视频",
                        context: highlightContext(extra: [
                            "itemIndex": "\(index + 1)",
                            "loadedVideoCount": "\(videos.count)",
                            "source": item.itemIdentifier == nil ? "pickerFile" : "photoLibrary",
                            "durationSeconds": Self.secondsString(video.duration),
                        ]),
                    )
                }

                selectedVideos = videos
            } catch {
                cleanupTemporaryVideos(videos)
                selectedItems = []
                logger.error(
                    "video.selection.failed",
                    category: .video,
                    message: "读取所选视频失败",
                    error: error,
                    context: highlightContext(extra: ["requestedItemCount": "\(items.count)"]),
                )
                alert = HighlightFlowAlert(
                    title: "无法读取视频",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                )
            }
        }

        @MainActor
        private func generateHighlight() async {
            let currentPlan = plan
            let segments = currentPlan.segments
            let totalMarkerCount = currentPlan.matchedMarkerCount
            guard !segments.isEmpty else {
                return
            }

            logger.info(
                "highlight.generate.started",
                category: .video,
                message: "开始生成集锦",
                context: highlightPlanContext(currentPlan, extra: [
                    "segmentCount": "\(segments.count)",
                    "secondsBeforeMarker": Self.secondsString(clipSettings.secondsBeforeMarker),
                    "secondsAfterMarker": Self.secondsString(clipSettings.secondsAfterMarker),
                ]),
            )
            isGenerating = true
            generationProgress = HighlightClipGenerationProgress(
                completedMarkerCount: 0,
                totalMarkerCount: totalMarkerCount,
            )
            var fallbackTemporaryVideoURLs: [URL] = []
            defer {
                isGenerating = false
                generationProgress = nil
                fallbackTemporaryVideoURLs.forEach { url in
                    try? FileManager.default.removeItem(at: url)
                }
            }

            do {
                if Self.requiresPhotoLibraryReadAccess(for: segments) {
                    try await Self.ensurePhotoLibraryReadAccess()
                }

                let pickerItemsByAssetIdentifier = Self.pickerItemsByAssetIdentifier(from: selectedItems)
                let outputURL = try await editingService.makeHighlightClip(
                    from: segments,
                    progressHandler: { progress in
                        generationProgress = progress
                        logger.info(
                            "highlight.generate.progress",
                            category: .video,
                            message: "集锦生成进度更新",
                            context: highlightContext(extra: [
                                "completedMarkerCount": "\(progress.completedMarkerCount)",
                                "totalMarkerCount": "\(progress.totalMarkerCount)",
                            ]),
                        )
                    },
                ) { request in
                    if let fileURL = Self.temporaryVideoURL(from: request.videoID) {
                        return AVURLAsset(url: fileURL)
                    }

                    let asset = try Self.photoAsset(with: request.videoID)
                    do {
                        return try await Self.requestAVAsset(
                            for: asset,
                            deliveryQuality: request.photoLibraryDeliveryQuality(
                                forSourceDuration: asset.duration,
                            ),
                        )
                    } catch {
                        guard PhotoLibraryVideoAccess.shouldFallbackToPickerFile(for: error),
                              let pickerItem = pickerItemsByAssetIdentifier[request.videoID]
                        else {
                            throw PhotoLibraryVideoAccess.userFacingError(for: error)
                        }

                        logger.warning(
                            "video.asset.fallback_to_picker_file",
                            category: .video,
                            message: "改用选择器临时文件读取视频",
                            context: highlightContext(extra: [
                                "requestedDurationSeconds": Self.secondsString(request.requestedDuration),
                            ]),
                        )
                        logger.info(
                            "video.asset.picker_file_load.started",
                            category: .video,
                            message: "开始读取选择器临时视频文件",
                            context: highlightContext(extra: [
                                "requestedDurationSeconds": Self.secondsString(request.requestedDuration),
                            ]),
                        )
                        let pickedVideoURL: URL
                        do {
                            pickedVideoURL = try await Self.loadTemporaryVideoURL(from: pickerItem)
                        } catch {
                            logger.error(
                                "video.asset.picker_file_load.failed",
                                category: .video,
                                message: "选择器临时视频文件读取失败",
                                error: error,
                                context: highlightContext(extra: [
                                    "requestedDurationSeconds": Self.secondsString(request.requestedDuration),
                                ]),
                            )
                            throw PhotoLibraryVideoAccess.userFacingError(for: error)
                        }
                        logger.info(
                            "video.asset.picker_file_load.succeeded",
                            category: .video,
                            message: "选择器临时视频文件读取成功",
                            context: highlightContext(extra: [
                                "requestedDurationSeconds": Self.secondsString(request.requestedDuration),
                            ]),
                        )
                        fallbackTemporaryVideoURLs.append(pickedVideoURL)
                        return AVURLAsset(url: pickedVideoURL)
                    }
                }
                try await photoLibrarySaver.saveVideo(at: outputURL)
                try? FileManager.default.removeItem(at: outputURL)
                cleanupTemporaryVideos()
                selectedItems = []
                selectedVideos = []
                logger.info(
                    "highlight.generate.succeeded",
                    category: .video,
                    message: "集锦生成成功",
                    context: highlightPlanContext(currentPlan, extra: ["segmentCount": "\(segments.count)"]),
                )
                alert = HighlightFlowAlert(title: "集锦已保存", message: "新视频已保存到相册。")
            } catch {
                logger.error(
                    "highlight.generate.failed",
                    category: .video,
                    message: "集锦生成失败",
                    error: error,
                    context: highlightPlanContext(currentPlan, extra: ["segmentCount": "\(segments.count)"]),
                )
                alert = HighlightFlowAlert(
                    title: "集锦生成失败",
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

        private func cleanupTemporaryVideos() {
            cleanupTemporaryVideos(selectedVideos)
        }

        private func cleanupTemporaryVideos(_ videos: [SelectedTrainingVideo]) {
            videos.compactMap { Self.temporaryVideoURL(from: $0.id) }.forEach { url in
                try? FileManager.default.removeItem(at: url)
            }
        }

        nonisolated private static func loadSelectedVideo(
            from item: PhotosPickerItem,
        ) async throws -> SelectedTrainingVideo {
            if let assetIdentifier = item.itemIdentifier {
                do {
                    try await ensurePhotoLibraryReadAccess()
                    return try selectedVideoFromPhotoLibraryAsset(with: assetIdentifier)
                } catch {
                    // PhotosPicker can still provide a scoped file copy even when PHAsset access is unavailable.
                }
            }

            guard let pickedVideo = try await item.loadTransferable(type: PickedTrainingVideo.self) else {
                throw HighlightVideoSelectionError.videoLoadFailed
            }

            let metadata = try await loadVideoMetadata(from: pickedVideo.url)
            return SelectedTrainingVideo(
                id: pickedVideo.url.absoluteString,
                recordedStartAt: metadata.recordedStartAt,
                duration: metadata.duration,
            )
        }

        nonisolated private static func selectedVideoFromPhotoLibraryAsset(
            with localIdentifier: String,
        ) throws -> SelectedTrainingVideo {
            let asset = try photoAsset(with: localIdentifier)
            let metadata = try loadVideoMetadata(from: asset)
            return SelectedTrainingVideo(
                id: asset.localIdentifier,
                recordedStartAt: metadata.recordedStartAt,
                duration: metadata.duration,
            )
        }

        nonisolated private static func ensurePhotoLibraryReadAccess() async throws {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            switch status {
            case .authorized, .limited:
                return
            case .notDetermined:
                let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                guard requestedStatus == .authorized || requestedStatus == .limited else {
                    throw HighlightVideoSelectionError.photoLibraryAccessDenied
                }
            case .denied, .restricted:
                throw HighlightVideoSelectionError.photoLibraryAccessDenied
            @unknown default:
                throw HighlightVideoSelectionError.photoLibraryAccessDenied
            }
        }

        nonisolated private static func photoAsset(with localIdentifier: String) throws -> PHAsset {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = result.firstObject else {
                throw HighlightVideoSelectionError.videoLoadFailed
            }

            return asset
        }

        nonisolated private static func loadVideoMetadata(from asset: PHAsset) throws -> TrainingVideoMetadata {
            guard let recordedStartAt = asset.creationDate else {
                throw HighlightVideoSelectionError.missingRecordedStartAt
            }

            guard asset.duration.isFinite, asset.duration > 0 else {
                throw HighlightVideoSelectionError.invalidDuration
            }

            return TrainingVideoMetadata(recordedStartAt: recordedStartAt, duration: asset.duration)
        }

        nonisolated private static func loadVideoMetadata(from url: URL) async throws -> TrainingVideoMetadata {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds

            guard duration.isFinite, duration > 0 else {
                throw HighlightVideoSelectionError.invalidDuration
            }

            guard let creationDateItem = try await asset.load(.creationDate),
                  let recordedStartAt = try await creationDateItem.load(.dateValue)
            else {
                throw HighlightVideoSelectionError.missingRecordedStartAt
            }

            return TrainingVideoMetadata(recordedStartAt: recordedStartAt, duration: duration)
        }

        nonisolated private static func requestAVAsset(
            for asset: PHAsset,
            deliveryQuality: HighlightClipPhotoLibraryDeliveryQuality,
        ) async throws -> AVAsset {
            try await PhotoLibraryVideoAccess.requestAVAsset(deliveryQuality: deliveryQuality) { options, completion in
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                    completion(avAsset, info)
                }
            }
        }

        nonisolated private static func loadTemporaryVideoURL(
            from item: PhotosPickerItem,
        ) async throws -> URL {
            guard let pickedVideo = try await PhotoLibraryVideoAccess.withTimeout(
                operation: {
                    try await item.loadTransferable(type: PickedTrainingVideo.self)
                },
            ) else {
                throw HighlightVideoSelectionError.videoLoadFailed
            }

            return pickedVideo.url
        }

        nonisolated private static func temporaryVideoURL(from videoID: String) -> URL? {
            guard let url = URL(string: videoID), url.isFileURL else {
                return nil
            }

            return url
        }

        nonisolated private static func requiresPhotoLibraryReadAccess(for segments: [HighlightClipSegment]) -> Bool {
            segments.contains { temporaryVideoURL(from: $0.videoID) == nil }
        }

        nonisolated private static func secondsString(_ value: TimeInterval) -> String {
            String(format: "%.3f", value)
        }

        nonisolated private static func pickerItemsByAssetIdentifier(
            from items: [PhotosPickerItem],
        ) -> [String: PhotosPickerItem] {
            items.reduce(into: [:]) { result, item in
                if let assetIdentifier = item.itemIdentifier {
                    result[assetIdentifier] = item
                }
            }
        }
    }

    private struct TrainingVideoMetadata {
        let recordedStartAt: Date
        let duration: TimeInterval
    }

    private struct HighlightFlowAlert {
        let title: String
        let message: String
    }

    private struct PickedTrainingVideo: Sendable, Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { video in
                SentTransferredFile(video.url)
            } importing: { received in
                let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
                let copyURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ShotMarker-TrainingVideo-\(UUID().uuidString).\(fileExtension)")

                let isAccessingSecurityScopedResource = received.file.startAccessingSecurityScopedResource()
                defer {
                    if isAccessingSecurityScopedResource {
                        received.file.stopAccessingSecurityScopedResource()
                    }
                }

                try FileManager.default.copyItem(at: received.file, to: copyURL)
                return PickedTrainingVideo(url: copyURL)
            }
        }
    }

    private enum HighlightVideoSelectionError: LocalizedError {
        case videoLoadFailed
        case photoLibraryAccessDenied
        case missingRecordedStartAt
        case invalidDuration

        var errorDescription: String? {
            switch self {
            case .videoLoadFailed:
                "无法读取选择的视频。"
            case .photoLibraryAccessDenied:
                "没有相册读取权限。请允许 ShotMarker 读取所选视频后再试。"
            case .missingRecordedStartAt:
                "所选视频缺少拍摄时间，暂时无法用于自动剪辑。"
            case .invalidDuration:
                "所选视频无法读取时长，请重新选择其他视频。"
            }
        }
    }

    #if DEBUG
        #Preview {
            NavigationStack {
                TrainingSessionHighlightView(session: TrainingSession.previewSessions[0])
            }
        }
    #endif
#endif

#if os(iOS)
    import AVFoundation
    import CoreTransferable
    import Foundation
    import Photos
    import PhotosUI
    import SwiftUI
    import UIKit
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
        @State private var selectedVideoItems: [SelectedTrainingVideoSelectionItem] = []
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
                        Label(selectedVideoItems.isEmpty ? "选择视频" : "继续选择视频", systemImage: "video.badge.plus")
                    }
                    .disabled(isLoadingVideos || isGenerating)

                    if isLoadingVideos {
                        ProgressView("读取视频")
                    }
                }

                if !selectedVideoItems.isEmpty {
                    Section("已选视频") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(selectedVideoItems) { item in
                                    selectedVideoItemCard(item)
                                }
                            }
                            .padding(.vertical, 4)
                        }
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

        private func selectedVideoItemCard(_ item: SelectedTrainingVideoSelectionItem) -> some View {
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
        private func loadSelectedVideos(from items: [PhotosPickerItem]) async {
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
                let selectionItem = await loadSelectedVideoItem(from: item, at: index)
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
                        let pickedVideoURL = try await Self.loadTemporaryVideoURL(from: pickerItem)
                        fallbackTemporaryVideoURLs.append(pickedVideoURL)
                        return AVURLAsset(url: pickedVideoURL)
                    }
                }
                try await photoLibrarySaver.saveVideo(at: outputURL)
                try? FileManager.default.removeItem(at: outputURL)
                cleanupTemporaryVideos()
                selectedItems = []
                selectedVideos = []
                selectedVideoItems = []
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

        @MainActor
        private func loadSelectedVideoItem(
            from item: PhotosPickerItem,
            at index: Int,
        ) async -> SelectedTrainingVideoSelectionItem {
            let title = "视频 \(index + 1)"
            let fallbackID = "selection-\(index + 1)"

            do {
                let loadedVideo = try await Self.loadSelectedVideoWithThumbnail(
                    from: item,
                    fallbackID: fallbackID,
                )
                guard VideoClipSegmentPlanner.canUseVideo(loadedVideo.video, for: session) else {
                    Self.removeTemporaryVideoIfNeeded(loadedVideo.video)
                    return .unavailable(
                        id: loadedVideo.video.id,
                        title: title,
                        reason: .noMarkerCoverage,
                        thumbnailData: loadedVideo.thumbnailData,
                    )
                }

                do {
                    try await Self.readyTrainingVideoChecker.ensureReady(loadedVideo.video)
                } catch {
                    return .unavailable(
                        id: loadedVideo.video.id,
                        title: title,
                        reason: .notReady,
                        thumbnailData: loadedVideo.thumbnailData,
                    )
                }

                return .available(
                    id: loadedVideo.video.id,
                    title: title,
                    video: loadedVideo.video,
                    thumbnailData: loadedVideo.thumbnailData,
                )
            } catch let failure as SelectedTrainingVideoLoadFailure {
                return .unavailable(
                    id: failure.id,
                    title: title,
                    reason: Self.unavailableReason(for: failure.error),
                    thumbnailData: failure.thumbnailData,
                )
            } catch {
                return .unavailable(
                    id: item.itemIdentifier ?? fallbackID,
                    title: title,
                    reason: Self.unavailableReason(for: error),
                    thumbnailData: nil,
                )
            }
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
            cleanupTemporaryVideos(selectedVideos)
        }

        private func cleanupTemporaryVideos(_ videos: [SelectedTrainingVideo]) {
            videos.compactMap { Self.temporaryVideoURL(from: $0.id) }.forEach { url in
                try? FileManager.default.removeItem(at: url)
            }
        }

        nonisolated private static func loadSelectedVideoWithThumbnail(
            from item: PhotosPickerItem,
            fallbackID: String,
        ) async throws -> LoadedTrainingVideo {
            var photoLibraryFailure: SelectedTrainingVideoLoadFailure?

            if let assetIdentifier = item.itemIdentifier {
                do {
                    try await ensurePhotoLibraryReadAccess()
                    let asset = try photoAsset(with: assetIdentifier)
                    let thumbnailData = await thumbnailData(from: asset)
                    do {
                        let metadata = try loadVideoMetadata(from: asset)
                        return LoadedTrainingVideo(
                            video: SelectedTrainingVideo(
                                id: asset.localIdentifier,
                                recordedStartAt: metadata.recordedStartAt,
                                duration: metadata.duration,
                            ),
                            thumbnailData: thumbnailData,
                        )
                    } catch {
                        throw SelectedTrainingVideoLoadFailure(
                            id: assetIdentifier,
                            thumbnailData: thumbnailData,
                            error: error,
                        )
                    }
                } catch let failure as SelectedTrainingVideoLoadFailure {
                    photoLibraryFailure = failure
                } catch {
                    // PhotosPicker can still provide a scoped file copy even when PHAsset access is unavailable.
                    photoLibraryFailure = SelectedTrainingVideoLoadFailure(
                        id: assetIdentifier,
                        thumbnailData: nil,
                        error: error,
                    )
                }
            }

            do {
                let pickedVideo = try await loadPickedTrainingVideo(from: item)
                let thumbnailData = await thumbnailData(from: pickedVideo.url)
                do {
                    let metadata = try await loadVideoMetadata(from: pickedVideo.url)
                    return LoadedTrainingVideo(
                        video: SelectedTrainingVideo(
                            id: pickedVideo.url.absoluteString,
                            recordedStartAt: metadata.recordedStartAt,
                            duration: metadata.duration,
                        ),
                        thumbnailData: thumbnailData,
                    )
                } catch {
                    try? FileManager.default.removeItem(at: pickedVideo.url)
                    throw SelectedTrainingVideoLoadFailure(
                        id: pickedVideo.url.absoluteString,
                        thumbnailData: thumbnailData,
                        error: error,
                    )
                }
            } catch let failure as SelectedTrainingVideoLoadFailure {
                throw failure
            } catch {
                throw photoLibraryFailure ?? SelectedTrainingVideoLoadFailure(
                    id: item.itemIdentifier ?? fallbackID,
                    thumbnailData: nil,
                    error: error,
                )
            }
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

        nonisolated private static func thumbnailData(from asset: PHAsset) async -> Data? {
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true

            var thumbnailData: Data?
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 320, height: 180),
                contentMode: .aspectFill,
                options: options,
            ) { image, _ in
                thumbnailData = image?.jpegData(compressionQuality: 0.72)
            }
            return thumbnailData
        }

        nonisolated private static func thumbnailData(from url: URL) async -> Data? {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)

            do {
                let image = try await cgImage(from: generator, at: .zero)
                return UIImage(cgImage: image).jpegData(compressionQuality: 0.72)
            } catch {
                return nil
            }
        }

        nonisolated private static func cgImage(
            from generator: AVAssetImageGenerator,
            at time: CMTime,
        ) async throws -> CGImage {
            try await withCheckedThrowingContinuation { continuation in
                generator.generateCGImageAsynchronously(for: time) { image, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let image else {
                        continuation.resume(throwing: HighlightVideoSelectionError.videoLoadFailed)
                        return
                    }

                    continuation.resume(returning: image)
                }
            }
        }

        nonisolated private static var readyTrainingVideoChecker: SelectedTrainingVideoReadinessChecker {
            SelectedTrainingVideoReadinessChecker { assetIdentifier in
                let asset = try photoAsset(with: assetIdentifier)
                try await requestLocalAVAsset(for: asset)
            }
        }

        nonisolated private static func requestAVAsset(
            for asset: PHAsset,
            deliveryQuality: HighlightClipPhotoLibraryDeliveryQuality,
        ) async throws -> AVAsset {
            let options = PHVideoRequestOptions()
            options.deliveryMode = deliveryQuality.photoVideoRequestDeliveryMode
            options.isNetworkAccessAllowed = true

            return try await withCheckedThrowingContinuation { continuation in
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                        return
                    }

                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        continuation.resume(throwing: HighlightVideoSelectionError.videoLoadFailed)
                        return
                    }

                    guard let avAsset else {
                        continuation.resume(throwing: HighlightVideoSelectionError.videoLoadFailed)
                        return
                    }

                    continuation.resume(returning: avAsset)
                }
            }
        }

        nonisolated private static func requestLocalAVAsset(for asset: PHAsset) async throws {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .mediumQualityFormat
            options.isNetworkAccessAllowed = false

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                        return
                    }

                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        continuation.resume(throwing: HighlightVideoSelectionError.videoLoadFailed)
                        return
                    }

                    guard avAsset != nil else {
                        continuation.resume(throwing: HighlightVideoSelectionError.videoNotReady)
                        return
                    }

                    continuation.resume()
                }
            }
        }

        nonisolated private static func loadTemporaryVideoURL(
            from item: PhotosPickerItem,
        ) async throws -> URL {
            try await loadPickedTrainingVideo(from: item).url
        }

        nonisolated private static func loadPickedTrainingVideo(
            from item: PhotosPickerItem,
        ) async throws -> PickedTrainingVideo {
            guard let pickedVideo = try await item.loadTransferable(type: PickedTrainingVideo.self) else {
                throw HighlightVideoSelectionError.videoLoadFailed
            }

            return pickedVideo
        }

        nonisolated private static func temporaryVideoURL(from videoID: String) -> URL? {
            SelectedTrainingVideoReadinessChecker.temporaryVideoURL(from: videoID)
        }

        nonisolated private static func removeTemporaryVideoIfNeeded(_ video: SelectedTrainingVideo) {
            guard let url = temporaryVideoURL(from: video.id) else {
                return
            }

            try? FileManager.default.removeItem(at: url)
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

        nonisolated private static func unavailableReason(for error: Error) -> SelectedTrainingVideoUnavailableReason {
            switch error as? HighlightVideoSelectionError {
            case .videoLoadFailed:
                .failedToLoad
            case .photoLibraryAccessDenied:
                .photoLibraryAccessDenied
            case .missingRecordedStartAt:
                .missingRecordedStartAt
            case .invalidDuration:
                .invalidDuration
            case .videoNotReady:
                .notReady
            case nil:
                .failedToLoad
            }
        }
    }

    private extension HighlightClipPhotoLibraryDeliveryQuality {
        nonisolated var photoVideoRequestDeliveryMode: PHVideoRequestOptionsDeliveryMode {
            switch self {
            case .high:
                .highQualityFormat
            case .medium:
                .mediumQualityFormat
            }
        }
    }

    private struct TrainingVideoMetadata {
        let recordedStartAt: Date
        let duration: TimeInterval
    }

    private struct LoadedTrainingVideo {
        let video: SelectedTrainingVideo
        let thumbnailData: Data?
    }

    private struct SelectedTrainingVideoLoadFailure: Error {
        let id: String
        let thumbnailData: Data?
        let error: Error
    }

    private struct HighlightFlowAlert {
        let title: String
        let message: String
    }

    private struct PickedTrainingVideo: Transferable {
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
        case videoNotReady

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
            case .videoNotReady:
                "所选视频还没有下载完成，暂时无法用于自动剪辑。"
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

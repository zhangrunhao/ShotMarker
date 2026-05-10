#if os(iOS)
    import AVFoundation
    import CoreTransferable
    import Photos
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers

    struct TrainingSessionHighlightView: View {
        let session: TrainingSession

        @State private var selectedItems: [PhotosPickerItem] = []
        @State private var selectedVideos: [SelectedTrainingVideo] = []
        @State private var isLoadingVideos = false
        @State private var isGenerating = false
        @State private var clipSettings = ClipSettingsStore.shared.load()
        @State private var generationProgress: HighlightClipGenerationProgress?
        @State private var alert: HighlightFlowAlert?

        private let editingService = VideoClipEditingService()
        private let photoLibrarySaver = VideoClipPhotoLibrarySaver()

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
            .onChange(of: clipSettings) { _, newSettings in
                ClipSettingsStore.shared.save(newSettings)
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

        @MainActor
        private func loadSelectedVideos(from items: [PhotosPickerItem]) async {
            cleanupTemporaryVideos()
            selectedVideos = []

            guard !items.isEmpty else {
                return
            }

            isLoadingVideos = true
            defer {
                isLoadingVideos = false
            }

            var videos: [SelectedTrainingVideo] = []

            do {
                for item in items {
                    let video = try await Self.loadSelectedVideo(from: item)
                    videos.append(video)
                }

                selectedVideos = videos
            } catch {
                cleanupTemporaryVideos(videos)
                selectedItems = []
                alert = HighlightFlowAlert(
                    title: "无法读取视频",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                )
            }
        }

        @MainActor
        private func generateHighlight() async {
            let segments = plan.segments
            let totalMarkerCount = plan.matchedMarkerCount
            guard !segments.isEmpty else {
                return
            }

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
                alert = HighlightFlowAlert(title: "集锦已保存", message: "新视频已保存到相册。")
            } catch {
                alert = HighlightFlowAlert(
                    title: "集锦生成失败",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                )
            }
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

        nonisolated private static func loadTemporaryVideoURL(
            from item: PhotosPickerItem,
        ) async throws -> URL {
            guard let pickedVideo = try await item.loadTransferable(type: PickedTrainingVideo.self) else {
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

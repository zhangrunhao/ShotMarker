#if os(iOS)
    import Foundation
    import PhotosUI
    import SwiftUI

    struct TrainingVideoMetadata {
        let recordedStartAt: Date
        let duration: TimeInterval
    }

    struct LoadedTrainingVideo {
        let video: SelectedTrainingVideo
        let thumbnailData: Data?
    }

    struct SelectedTrainingVideoLoadFailure: Error {
        let id: String
        let thumbnailData: Data?
        let error: Error
    }

    enum HighlightVideoSelectionError: LocalizedError {
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

    struct TrainingVideoLoadingService<SelectionItem> {
        private let assetIdentifier: (SelectionItem) -> String?
        private let loadPhotoLibraryVideo: (String) async throws -> LoadedTrainingVideo
        private let loadPickedVideo: (SelectionItem) async throws -> LoadedTrainingVideo
        private let ensureReady: (SelectedTrainingVideo) async throws -> Void
        private let removeTemporaryVideoIfNeeded: (SelectedTrainingVideo) -> Void

        init(
            assetIdentifier: @escaping (SelectionItem) -> String?,
            loadPhotoLibraryVideo: @escaping (String) async throws -> LoadedTrainingVideo,
            loadPickedVideo: @escaping (SelectionItem) async throws -> LoadedTrainingVideo,
            ensureReady: @escaping (SelectedTrainingVideo) async throws -> Void,
            removeTemporaryVideoIfNeeded: @escaping (SelectedTrainingVideo) -> Void,
        ) {
            self.assetIdentifier = assetIdentifier
            self.loadPhotoLibraryVideo = loadPhotoLibraryVideo
            self.loadPickedVideo = loadPickedVideo
            self.ensureReady = ensureReady
            self.removeTemporaryVideoIfNeeded = removeTemporaryVideoIfNeeded
        }

        func loadSelectionItem(
            from item: SelectionItem,
            title: String,
            fallbackID: String,
            session: TrainingSession,
        ) async -> SelectedTrainingVideoSelectionItem {
            do {
                let loadedVideo = try await loadVideo(from: item, fallbackID: fallbackID)
                guard VideoClipSegmentPlanner.canUseVideo(loadedVideo.video, for: session) else {
                    removeTemporaryVideoIfNeeded(loadedVideo.video)
                    return .unavailable(
                        id: loadedVideo.video.id,
                        title: title,
                        reason: .noMarkerCoverage,
                        thumbnailData: loadedVideo.thumbnailData,
                    )
                }

                do {
                    try await ensureReady(loadedVideo.video)
                } catch {
                    return .unavailable(
                        id: loadedVideo.video.id,
                        title: title,
                        video: loadedVideo.video,
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
                    id: assetIdentifier(item) ?? fallbackID,
                    title: title,
                    reason: Self.unavailableReason(for: error),
                    thumbnailData: nil,
                )
            }
        }

        private func loadVideo(
            from item: SelectionItem,
            fallbackID: String,
        ) async throws -> LoadedTrainingVideo {
            var photoLibraryFailure: SelectedTrainingVideoLoadFailure?

            if let assetIdentifier = assetIdentifier(item) {
                do {
                    return try await loadPhotoLibraryVideo(assetIdentifier)
                } catch let failure as SelectedTrainingVideoLoadFailure {
                    photoLibraryFailure = failure
                } catch {
                    photoLibraryFailure = SelectedTrainingVideoLoadFailure(
                        id: assetIdentifier,
                        thumbnailData: nil,
                        error: error,
                    )
                }
            }

            do {
                return try await loadPickedVideo(item)
            } catch let failure as SelectedTrainingVideoLoadFailure {
                throw failure
            } catch {
                throw photoLibraryFailure ?? SelectedTrainingVideoLoadFailure(
                    id: assetIdentifier(item) ?? fallbackID,
                    thumbnailData: nil,
                    error: error,
                )
            }
        }

        private static func unavailableReason(for error: Error) -> SelectedTrainingVideoUnavailableReason {
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

    extension TrainingVideoLoadingService where SelectionItem == PhotosPickerItem {
        static func live(
            photoLibraryAssetProvider: PhotoLibraryVideoAssetProvider,
            temporaryFileStore: TrainingVideoTemporaryFileStore,
        ) -> TrainingVideoLoadingService<PhotosPickerItem> {
            let readinessChecker = SelectedTrainingVideoReadinessChecker { assetIdentifier in
                let asset = try photoLibraryAssetProvider.photoAsset(with: assetIdentifier)
                try await photoLibraryAssetProvider.requestLocalAVAsset(for: asset)
            }

            return TrainingVideoLoadingService<PhotosPickerItem>(
                assetIdentifier: { $0.itemIdentifier },
                loadPhotoLibraryVideo: { assetIdentifier in
                    try await photoLibraryAssetProvider.ensureReadAccess()
                    let asset = try photoLibraryAssetProvider.photoAsset(with: assetIdentifier)
                    let thumbnailData = await photoLibraryAssetProvider.thumbnailData(from: asset)
                    do {
                        let metadata = try photoLibraryAssetProvider.metadata(from: asset)
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
                },
                loadPickedVideo: { item in
                    let pickedVideo = try await temporaryFileStore.loadPickedTrainingVideo(from: item)
                    let thumbnailData = await temporaryFileStore.thumbnailData(from: pickedVideo.url)
                    do {
                        let metadata = try await temporaryFileStore.metadata(from: pickedVideo.url)
                        return LoadedTrainingVideo(
                            video: SelectedTrainingVideo(
                                id: pickedVideo.url.absoluteString,
                                recordedStartAt: metadata.recordedStartAt,
                                duration: metadata.duration,
                            ),
                            thumbnailData: thumbnailData,
                        )
                    } catch {
                        temporaryFileStore.removeTemporaryVideo(at: pickedVideo.url)
                        throw SelectedTrainingVideoLoadFailure(
                            id: pickedVideo.url.absoluteString,
                            thumbnailData: thumbnailData,
                            error: error,
                        )
                    }
                },
                ensureReady: { video in
                    try await readinessChecker.ensureReady(video)
                },
                removeTemporaryVideoIfNeeded: { video in
                    temporaryFileStore.removeTemporaryVideoIfNeeded(video)
                },
            )
        }
    }
#endif

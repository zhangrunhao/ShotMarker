#if os(iOS)
    import Foundation
    import Photos

    struct VideoClipPhotoLibrarySaver {
        private let requestAuthorization: () async -> PHAuthorizationStatus
        private let saveVideoToLibrary: (URL) async throws -> Void

        init(
            requestAuthorization: @escaping () async -> PHAuthorizationStatus = {
                await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            },
            saveVideoToLibrary: @escaping (URL) async throws -> Void = { videoURL in
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }
            },
        ) {
            self.requestAuthorization = requestAuthorization
            self.saveVideoToLibrary = saveVideoToLibrary
        }

        func saveVideo(at videoURL: URL) async throws {
            let status = await requestAuthorization()
            guard status == .authorized || status == .limited else {
                throw VideoClipPhotoLibraryError.accessDenied
            }

            try await saveVideoToLibrary(videoURL)
        }
    }

    enum VideoClipPhotoLibraryError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            "没有相册保存权限。请允许 ShotMarker 添加照片后再试。"
        }
    }
#endif

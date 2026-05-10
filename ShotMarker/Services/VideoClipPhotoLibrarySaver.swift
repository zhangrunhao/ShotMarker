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

    enum PhotoLibraryVideoAccessError: LocalizedError, Equatable {
        case networkUnavailable

        var errorDescription: String? {
            switch self {
            case .networkUnavailable:
                "无法从 iCloud 读取所选视频。请确认网络可用，或先在照片 App 打开这个视频让它下载完成后再试。"
            }
        }
    }

    enum PhotoLibraryVideoAccess {
        private static let networkErrorCode = 3169

        static func shouldFallbackToPickerFile(for error: Error) -> Bool {
            isPhotoLibraryNetworkError(error)
        }

        static func userFacingError(for error: Error) -> Error {
            if isPhotoLibraryNetworkError(error) {
                return PhotoLibraryVideoAccessError.networkUnavailable
            }

            return error
        }

        private static func isPhotoLibraryNetworkError(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == PHPhotosErrorDomain && nsError.code == networkErrorCode
        }
    }
#endif

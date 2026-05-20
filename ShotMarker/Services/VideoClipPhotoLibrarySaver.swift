#if os(iOS)
    import AVFoundation
    import Foundation
    import Photos

    struct VideoClipPhotoLibrarySaver {
        private let requestAuthorization: () async -> PHAuthorizationStatus
        private let saveVideoToLibrary: (URL) async throws -> Void
        private let logger: AppLogging

        init(
            requestAuthorization: @escaping () async -> PHAuthorizationStatus = {
                await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            },
            saveVideoToLibrary: @escaping (URL) async throws -> Void = { videoURL in
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }
            },
            logger: AppLogging = AppLogger.shared,
        ) {
            self.requestAuthorization = requestAuthorization
            self.saveVideoToLibrary = saveVideoToLibrary
            self.logger = logger
        }

        func saveVideo(at videoURL: URL) async throws {
            logger.info(
                "photos.save.authorization.requested",
                category: .photos,
                message: "请求相册保存权限",
            )
            let status = await requestAuthorization()
            guard status == .authorized || status == .limited else {
                logger.warning(
                    "photos.save.authorization.denied",
                    category: .photos,
                    message: "相册保存权限被拒绝",
                    context: ["authorizationStatus": status.logDescription],
                )
                throw VideoClipPhotoLibraryError.accessDenied
            }

            do {
                try await saveVideoToLibrary(videoURL)
                logger.info(
                    "photos.save.succeeded",
                    category: .photos,
                    message: "视频已保存到相册",
                    context: ["authorizationStatus": status.logDescription],
                )
            } catch {
                logger.error(
                    "photos.save.failed",
                    category: .photos,
                    message: "视频保存到相册失败",
                    error: error,
                    context: ["authorizationStatus": status.logDescription],
                )
                throw error
            }
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
        case requestTimedOut

        var errorDescription: String? {
            switch self {
            case .networkUnavailable:
                "无法从 iCloud 读取所选视频。请确认网络可用，或先在照片 App 打开这个视频让它下载完成后再试。"
            case .requestTimedOut:
                "系统相册无法读取所选视频的高质量版本，常见于 iCloud 未下载或相册内裁剪、调整后的视频。请先在照片 App 打开并等待下载完成，或导出/复制为新视频后再选择。"
            }
        }
    }

    enum PhotoLibraryVideoAccess {
        private static let networkErrorCode = 3169

        typealias AssetRequestCompletion = (AVAsset?, [AnyHashable: Any]?) -> Void
        typealias AssetRequestStarter = (PHVideoRequestOptions, @escaping AssetRequestCompletion) -> PHImageRequestID
        typealias AssetRequestCanceller = (PHImageRequestID) -> Void

        static func shouldFallbackToPickerFile(for error: Error) -> Bool {
            isPhotoLibraryNetworkError(error) || isRequestTimeout(error)
        }

        static func userFacingError(for error: Error) -> Error {
            if isPhotoLibraryNetworkError(error) {
                return PhotoLibraryVideoAccessError.networkUnavailable
            }

            if isRequestTimeout(error) {
                return PhotoLibraryVideoAccessError.requestTimedOut
            }

            return error
        }

        static func requestAVAsset(
            deliveryQuality: HighlightClipPhotoLibraryDeliveryQuality,
            timeout: Duration = .seconds(30),
            startRequest: @escaping AssetRequestStarter,
            cancelRequest: @escaping AssetRequestCanceller = { requestID in
                PHImageManager.default().cancelImageRequest(requestID)
            },
        ) async throws -> AVAsset {
            let options = PHVideoRequestOptions()
            options.deliveryMode = deliveryQuality.photoVideoRequestDeliveryMode
            options.isNetworkAccessAllowed = true
            options.version = .current

            let requestState = PhotoLibraryVideoRequestState()
            return try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task {
                    try? await Task.sleep(for: timeout)

                    let resolution = requestState.resolve()
                    guard resolution.didResolve else {
                        return
                    }

                    if let requestID = resolution.requestID {
                        cancelRequest(requestID)
                    }
                    continuation.resume(throwing: PhotoLibraryVideoAccessError.requestTimedOut)
                }

                let requestID = startRequest(options) { avAsset, info in
                    let resolution = requestState.resolve()
                    guard resolution.didResolve else {
                        return
                    }

                    timeoutTask.cancel()

                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                        return
                    }

                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        continuation.resume(throwing: PhotoLibraryVideoAccessError.requestTimedOut)
                        return
                    }

                    guard let avAsset else {
                        continuation.resume(throwing: PhotoLibraryVideoAccessError.requestTimedOut)
                        return
                    }

                    continuation.resume(returning: avAsset)
                }
                requestState.setRequestID(requestID)
            }
        }

        static func withTimeout<T: Sendable>(
            timeout: Duration = .seconds(30),
            operation: @escaping @Sendable () async throws -> T,
        ) async throws -> T {
            let state = PhotoLibraryVideoTimeoutState()
            return try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task.detached {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }

                    guard state.resolve() else {
                        return
                    }

                    state.cancelOperation()
                    continuation.resume(throwing: PhotoLibraryVideoAccessError.requestTimedOut)
                }
                state.setTimeoutTask(timeoutTask)

                let operationTask = Task.detached {
                    do {
                        let value = try await operation()
                        guard state.resolve() else {
                            return
                        }

                        state.cancelTimeout()
                        continuation.resume(returning: value)
                    } catch {
                        guard state.resolve() else {
                            return
                        }

                        state.cancelTimeout()
                        continuation.resume(throwing: error)
                    }
                }
                state.setOperationTask(operationTask)
            }
        }

        private static func isPhotoLibraryNetworkError(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == PHPhotosErrorDomain && nsError.code == networkErrorCode
        }

        private static func isRequestTimeout(_ error: Error) -> Bool {
            error as? PhotoLibraryVideoAccessError == .requestTimedOut
        }
    }

    nonisolated private final class PhotoLibraryVideoRequestState: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false
        private var requestID: PHImageRequestID?

        func setRequestID(_ requestID: PHImageRequestID) {
            lock.lock()
            self.requestID = requestID
            lock.unlock()
        }

        func resolve() -> (didResolve: Bool, requestID: PHImageRequestID?) {
            lock.lock()
            defer { lock.unlock() }

            guard !didResume else {
                return (false, nil)
            }

            didResume = true
            return (true, requestID)
        }
    }

    nonisolated private final class PhotoLibraryVideoTimeoutState: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false
        private var operationTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?

        func setOperationTask(_ task: Task<Void, Never>) {
            lock.lock()
            if didResume {
                lock.unlock()
                task.cancel()
                return
            }

            operationTask = task
            lock.unlock()
        }

        func setTimeoutTask(_ task: Task<Void, Never>) {
            lock.lock()
            if didResume {
                lock.unlock()
                task.cancel()
                return
            }

            timeoutTask = task
            lock.unlock()
        }

        func resolve() -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard !didResume else {
                return false
            }

            didResume = true
            return true
        }

        func cancelOperation() {
            lock.lock()
            let task = operationTask
            lock.unlock()
            task?.cancel()
        }

        func cancelTimeout() {
            lock.lock()
            let task = timeoutTask
            lock.unlock()
            task?.cancel()
        }
    }

    private extension HighlightClipPhotoLibraryDeliveryQuality {
        var photoVideoRequestDeliveryMode: PHVideoRequestOptionsDeliveryMode {
            switch self {
            case .high:
                .highQualityFormat
            case .medium:
                .mediumQualityFormat
            }
        }
    }

    private extension PHAuthorizationStatus {
        var logDescription: String {
            switch self {
            case .notDetermined:
                "notDetermined"
            case .restricted:
                "restricted"
            case .denied:
                "denied"
            case .authorized:
                "authorized"
            case .limited:
                "limited"
            @unknown default:
                "unknown"
            }
        }
    }
#endif

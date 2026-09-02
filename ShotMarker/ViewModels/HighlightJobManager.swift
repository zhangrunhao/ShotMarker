import AVFoundation
import Combine
import Foundation
#if os(iOS)
    import Photos
#endif

@MainActor
final class HighlightJobManager: ObservableObject {
    @Published private(set) var jobs: [HighlightJob] = []
    @Published private(set) var photoLibrarySavingJobIDs: Set<UUID> = []

    private let store: HighlightJobStoreProtocol
    private let fileStore: HighlightJobFileStoreProtocol
    private let runnerFactory: (HighlightJob) -> HighlightJobRunner
    private let saveVideoToPhotoLibrary: (URL) async throws -> Void
    private let logger: AppLogging
    private let analytics: AnalyticsTracking
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    init(
        store: HighlightJobStoreProtocol,
        fileStore: HighlightJobFileStoreProtocol,
        runnerFactory: @escaping (HighlightJob) -> HighlightJobRunner,
        saveVideoToPhotoLibrary: @escaping (URL) async throws -> Void = { _ in },
        logger: AppLogging = AppLogger.shared,
        analytics: AnalyticsTracking = NoopAnalyticsTracker(),
    ) {
        self.store = store
        self.fileStore = fileStore
        self.runnerFactory = runnerFactory
        self.saveVideoToPhotoLibrary = saveVideoToPhotoLibrary
        self.logger = logger
        self.analytics = analytics
    }

    #if os(iOS)
        static func live(
            logger: AppLogging = AppLogger.shared,
            analytics: AnalyticsTracking = NoopAnalyticsTracker(),
        ) -> HighlightJobManager {
            let store = HighlightJobStore()
            let fileStore = HighlightJobFileStore()
            let photoLibraryAssetProvider = PhotoLibraryVideoAssetProvider()
            let photoLibrarySaver = VideoClipPhotoLibrarySaver(logger: logger)
            let editingService = VideoClipEditingService(logger: logger)

            return HighlightJobManager(
                store: store,
                fileStore: fileStore,
                runnerFactory: { _ in
                    HighlightJobRunner(
                        fileStore: fileStore,
                        makeHighlightClip: { segments, markerLabelStyle, progressHandler, assetProvider in
                            try await editingService.makeHighlightClip(
                                from: segments,
                                markerLabelStyle: markerLabelStyle,
                                progressHandler: progressHandler,
                                assetProvider,
                            )
                        },
                        assetForJobVideo: { jobVideo, request in
                            switch jobVideo.source {
                            case let .photoLibraryAsset(localIdentifier):
                                try await photoLibraryAssetProvider.ensureReadAccess()
                                let asset = try photoLibraryAssetProvider.photoAsset(with: localIdentifier)
                                return try await photoLibraryAssetProvider.requestAVAsset(
                                    for: asset,
                                    deliveryQuality: request.photoLibraryDeliveryQuality(forSourceDuration: asset.duration),
                                )
                            case let .jobInputFile(relativePath):
                                return AVURLAsset(url: try fileStore.url(forRelativePath: relativePath))
                            }
                        },
                    )
                },
                saveVideoToPhotoLibrary: { outputURL in
                    try await photoLibrarySaver.saveVideo(at: outputURL)
                },
                logger: logger,
                analytics: analytics,
            )
        }
    #endif

    func load() {
        do {
            jobs = try store.loadJobsForLaunchRecovery()
            persist()
        } catch {
            jobs = []
        }
    }

    @discardableResult
    func createJob(
        session: TrainingSession,
        selectedVideos: [SelectedTrainingVideo],
        clipSettings: ClipSettings,
        confirmedSegments: [ConfirmedHighlightSegment],
    ) async throws -> HighlightJob {
        let validatedSegments = try HighlightClipReviewPlanner.validateConfirmedSegments(
            confirmedSegments,
            videos: selectedVideos,
            validMarkerIDs: Set(session.events.map(\.id)),
        )
        let referencedVideoIDs = Set(validatedSegments.map(\.videoID))
        let retainedVideos = selectedVideos.filter { referencedVideoIDs.contains($0.id) }
        let now = Date()
        let jobID = UUID()

        do {
            let jobVideos = try retainedVideos.map { video in
                try makeJobVideo(from: video, jobID: jobID)
            }
            let job = HighlightJob(
                id: jobID,
                trainingSession: session,
                selectedVideos: jobVideos,
                clipSettings: clipSettings.normalized,
                clipPlanVersion: 1,
                confirmedSegments: validatedSegments,
                status: .queued,
                progress: .zero,
                outputVideoPath: nil,
                photoLibrarySavedAt: nil,
                photoLibrarySaveErrorMessage: nil,
                errorMessage: nil,
                createdAt: now,
                updatedAt: now,
            )

            jobs.insert(job, at: 0)
            persist()
            logger.info(
                "highlight.job.queued",
                category: .video,
                message: "集锦任务已加入队列",
                context: [
                    "segmentCount": "\(validatedSegments.count)",
                    "videoCount": "\(retainedVideos.count)",
                    "markerCount": "\(validatedSegments.reduce(0) { $0 + $1.markerIDs.count })",
                    "totalDurationSeconds": String(
                        format: "%.1f",
                        validatedSegments.reduce(0) { $0 + $1.duration },
                    ),
                ],
            )
            startNextQueuedJobIfPossible()
            return job
        } catch {
            try? fileStore.removeAllFiles(for: jobID)
            throw error
        }
    }

    func cancel(jobID: UUID) {
        let didRemoveJob = jobs.contains { $0.id == jobID }
        runningTasks[jobID]?.cancel()
        runningTasks[jobID] = nil
        removePhotoLibrarySavingJobID(jobID)
        try? fileStore.removeAllFiles(for: jobID)
        jobs.removeAll { $0.id == jobID }
        persist()
        if didRemoveJob {
            logger.info(
                "highlight.job.cancelled",
                category: .video,
                message: "集锦任务已取消",
                context: ["jobID": jobID.uuidString],
            )
        }
        startNextQueuedJobIfPossible()
    }

    func restart(jobID: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }

        try? fileStore.removeOutput(for: jobID)
        jobs[index].status = .queued
        jobs[index].progress = .zero
        jobs[index].outputVideoPath = nil
        jobs[index].photoLibrarySavedAt = nil
        jobs[index].photoLibrarySaveErrorMessage = nil
        jobs[index].errorMessage = nil
        jobs[index].updatedAt = Date()
        persist()
        logger.info(
            "highlight.job.restarted",
            category: .video,
            message: "集锦任务重新开始",
            context: ["jobID": jobID.uuidString],
        )
        startNextQueuedJobIfPossible()
    }

    func clear(jobID: UUID) {
        let didRemoveJob = jobs.contains { $0.id == jobID }
        runningTasks[jobID]?.cancel()
        runningTasks[jobID] = nil
        removePhotoLibrarySavingJobID(jobID)
        try? fileStore.removeAllFiles(for: jobID)
        jobs.removeAll { $0.id == jobID }
        persist()
        if didRemoveJob {
            logger.info(
                "highlight.job.cleared",
                category: .video,
                message: "集锦任务已清理",
                context: ["jobID": jobID.uuidString],
            )
        }
        startNextQueuedJobIfPossible()
    }

    func playbackURL(for jobID: UUID) throws -> URL {
        guard let job = jobs.first(where: { $0.id == jobID }),
              let outputVideoPath = job.outputVideoPath
        else {
            throw HighlightJobFileStoreError.missingFile
        }

        let url = try fileStore.url(forRelativePath: outputVideoPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            markJobFailed(jobID: jobID, message: "本地视频文件不存在，请重新生成。")
            throw HighlightJobFileStoreError.missingFile
        }

        return url
    }

    func saveToPhotoLibrary(jobID: UUID) async {
        guard !photoLibrarySavingJobIDs.contains(jobID),
              let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].status == .completed
        else {
            return
        }

        guard let outputVideoPath = jobs[index].outputVideoPath else {
            markJobFailed(jobID: jobID, message: "本地视频文件不存在，请重新生成。")
            return
        }

        jobs[index].photoLibrarySaveErrorMessage = nil
        jobs[index].updatedAt = Date()
        persist()
        addPhotoLibrarySavingJobID(jobID)

        defer {
            removePhotoLibrarySavingJobID(jobID)
        }

        do {
            let outputURL = try fileStore.url(forRelativePath: outputVideoPath)
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                markJobFailed(jobID: jobID, message: "本地视频文件不存在，请重新生成。")
                return
            }

            try await saveVideoToPhotoLibrary(outputURL)
            guard let updatedIndex = jobs.firstIndex(where: { $0.id == jobID }) else {
                return
            }

            jobs[updatedIndex].photoLibrarySavedAt = Date()
            jobs[updatedIndex].photoLibrarySaveErrorMessage = nil
            jobs[updatedIndex].updatedAt = Date()
            guard persist() else {
                return
            }
            analytics.track(.highlightSaveSucceeded)
            logger.info(
                "highlight.job.photo_library_save.succeeded",
                category: .photos,
                message: "集锦任务已保存到相册",
                context: ["jobID": jobID.uuidString],
            )
        } catch {
            guard let updatedIndex = jobs.firstIndex(where: { $0.id == jobID }) else {
                return
            }

            jobs[updatedIndex].photoLibrarySaveErrorMessage = Self.userFacingMessage(for: error)
            jobs[updatedIndex].updatedAt = Date()
            persist()
            logger.error(
                "highlight.job.photo_library_save.failed",
                category: .photos,
                message: "集锦任务保存到相册失败",
                error: error,
                context: ["jobID": jobID.uuidString],
            )
        }
    }

    private func makeJobVideo(from video: SelectedTrainingVideo, jobID: UUID) throws -> HighlightJobVideo {
        if let sourceURL = URL(string: video.id), sourceURL.isFileURL {
            let relativePath = try fileStore.copyInputVideo(at: sourceURL, jobID: jobID, videoID: video.id)
            return HighlightJobVideo(
                id: video.id,
                recordedStartAt: video.recordedStartAt,
                duration: video.duration,
                source: .jobInputFile(relativePath: relativePath),
            )
        }

        return HighlightJobVideo(
            id: video.id,
            recordedStartAt: video.recordedStartAt,
            duration: video.duration,
            source: .photoLibraryAsset(localIdentifier: video.id),
        )
    }

    private func startNextQueuedJobIfPossible() {
        guard runningTasks.isEmpty,
              let job = jobs.first(where: { $0.status == .queued })
        else {
            return
        }

        let runner = runnerFactory(job)
        let task = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let finalJob = try await runner.run(job: job) { updatedJob in
                    self.update(updatedJob)
                }
                try Task.checkCancellation()
                self.update(finalJob)
                if finalJob.status == .completed {
                    analytics.track(.highlightGenerateSucceeded)
                }
            } catch is CancellationError {
                jobs.removeAll { $0.id == job.id }
                persist()
            } catch {
                markJobFailed(jobID: job.id, message: error.localizedDescription)
            }

            runningTasks[job.id] = nil
            startNextQueuedJobIfPossible()
        }
        runningTasks[job.id] = task
    }

    private func update(_ job: HighlightJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            return
        }

        jobs[index] = job
        persist()
    }

    private func markJobFailed(jobID: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }

        jobs[index].status = .failed
        jobs[index].errorMessage = message
        jobs[index].updatedAt = Date()
        persist()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try store.saveJobs(jobs)
            return true
        } catch {
            return false
        }
    }

    private func addPhotoLibrarySavingJobID(_ jobID: UUID) {
        var savingJobIDs = photoLibrarySavingJobIDs
        savingJobIDs.insert(jobID)
        photoLibrarySavingJobIDs = savingJobIDs
    }

    private func removePhotoLibrarySavingJobID(_ jobID: UUID) {
        var savingJobIDs = photoLibrarySavingJobIDs
        savingJobIDs.remove(jobID)
        photoLibrarySavingJobIDs = savingJobIDs
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

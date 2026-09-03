import AVFoundation
import Foundation

struct HighlightJobRunner {
    typealias MakeHighlightClip = (
        [HighlightClipSegment],
        MarkerLabelStyle,
        @MainActor @escaping (HighlightClipGenerationProgress) -> Void,
        @escaping (HighlightClipAssetRequest) async throws -> AVAsset
    ) async throws -> URL
    typealias RunOverride = @MainActor (
        HighlightJob,
        @MainActor @escaping (HighlightJob) -> Void
    ) async throws -> HighlightJob

    private let fileStore: HighlightJobFileStoreProtocol
    private let makeHighlightClip: MakeHighlightClip
    private let assetForJobVideo: (HighlightJobVideo, HighlightClipAssetRequest) async throws -> AVAsset
    private let runOverride: RunOverride?

    init(
        fileStore: HighlightJobFileStoreProtocol = HighlightJobFileStore(),
        makeHighlightClip: @escaping MakeHighlightClip,
        assetForJobVideo: @escaping (HighlightJobVideo, HighlightClipAssetRequest) async throws -> AVAsset,
    ) {
        self.fileStore = fileStore
        self.makeHighlightClip = makeHighlightClip
        self.assetForJobVideo = assetForJobVideo
        runOverride = nil
    }

    init(
        makeHighlightClip: @escaping MakeHighlightClip,
        runOverride: @escaping RunOverride,
    ) {
        fileStore = HighlightJobFileStore()
        self.makeHighlightClip = makeHighlightClip
        assetForJobVideo = { _, _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/unused.mov")) }
        self.runOverride = runOverride
    }

    @MainActor
    func run(
        job originalJob: HighlightJob,
        onChange: @escaping @MainActor (HighlightJob) -> Void,
    ) async throws -> HighlightJob {
        if let runOverride {
            return try await runOverride(originalJob, onChange)
        }

        var job = originalJob
        job.status = .running
        job.progress = .zero
        job.errorMessage = nil
        job.updatedAt = Date()
        onChange(job)

        do {
            let selectedVideos = job.selectedVideos.map(\.selectedTrainingVideo)
            let segments: [HighlightClipSegment]
            switch (job.clipPlanVersion, job.confirmedSegments) {
            case (nil, nil):
                let legacy = VideoClipSegmentPlanner.highlightPlan(
                    for: job.trainingSession,
                    videos: selectedVideos,
                    clipSettings: job.clipSettings,
                )
                guard legacy.canGenerate else {
                    throw HighlightJobRunnerError.noMatchedMarkers
                }
                segments = legacy.segments
            case (nil, .some):
                throw HighlightJobClipPlanError.snapshotWithoutVersion
            case (1, nil):
                throw HighlightJobClipPlanError.missingVersionOneSnapshot
            case (1, .some(let confirmed)):
                do {
                    segments = try HighlightClipReviewPlanner.validateConfirmedSegments(
                        confirmed,
                        videos: selectedVideos,
                        validMarkerIDs: Set(job.trainingSession.events.map(\.id)),
                    ).map(\.highlightClipSegment)
                } catch {
                    throw HighlightJobClipPlanError.invalidVersionOneSnapshot
                }
            case (.some, _):
                throw HighlightJobClipPlanError.unsupportedVersion
            }

            let videosByID = Dictionary(uniqueKeysWithValues: job.selectedVideos.map { ($0.id, $0) })
            try Task.checkCancellation()
            let temporaryOutputURL = try await makeHighlightClip(
                segments,
                job.clipSettings.markerLabelStyle,
                { progress in
                    job.progress = HighlightJobProgress(
                        completedMarkerCount: progress.completedMarkerCount,
                        totalMarkerCount: progress.totalMarkerCount,
                    )
                    job.updatedAt = Date()
                    onChange(job)
                },
                { request in
                    guard let video = videosByID[request.videoID] else {
                        throw HighlightJobRunnerError.sourceVideoMissing
                    }

                    return try await assetForJobVideo(video, request)
                },
            )

            let outputRelativePath = try fileStore.moveOutputVideo(at: temporaryOutputURL, jobID: job.id)
            job.outputVideoPath = outputRelativePath
            job.status = .completed
            let markerCount = segments.reduce(0) { $0 + $1.coveredMarkerCount }
            job.progress = HighlightJobProgress(
                completedMarkerCount: markerCount,
                totalMarkerCount: markerCount,
            )
            job.updatedAt = Date()
            onChange(job)
            return job
        } catch is CancellationError {
            try? fileStore.removeOutput(for: job.id)
            throw CancellationError()
        } catch {
            try? fileStore.removeOutput(for: job.id)
            job.outputVideoPath = nil
            job.status = .failed
            job.errorMessage = Self.userFacingMessage(for: error)
            job.updatedAt = Date()
            onChange(job)
            return job
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

enum HighlightJobRunnerError: LocalizedError, Equatable {
    case noMatchedMarkers
    case sourceVideoMissing

    var errorDescription: String? {
        switch self {
        case .noMatchedMarkers:
            "所选视频没有覆盖任何打点。"
        case .sourceVideoMissing:
            "找不到任务使用的视频，请重新选择视频。"
        }
    }
}

enum HighlightJobClipPlanError: LocalizedError, Equatable {
    case snapshotWithoutVersion
    case missingVersionOneSnapshot
    case invalidVersionOneSnapshot
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .snapshotWithoutVersion:
            "任务缺少片段计划版本，请重新创建集锦。"
        case .missingVersionOneSnapshot:
            "任务缺少已确认片段，请重新创建集锦。"
        case .invalidVersionOneSnapshot:
            "任务的已确认片段无效，请重新创建集锦。"
        case .unsupportedVersion:
            "任务使用了不支持的片段计划版本，请重新创建集锦。"
        }
    }
}

import AVFoundation
import Foundation

struct HighlightJobRunner {
    typealias MakeHighlightClip = (
        [HighlightClipSegment],
        @MainActor @escaping (HighlightClipGenerationProgress) -> Void,
        @escaping (HighlightClipAssetRequest) async throws -> AVAsset
    ) async throws -> URL

    private let fileStore: HighlightJobFileStoreProtocol
    private let makeHighlightClip: MakeHighlightClip
    private let saveVideo: (URL) async throws -> Void
    private let assetForJobVideo: (HighlightJobVideo, HighlightClipAssetRequest) async throws -> AVAsset

    init(
        fileStore: HighlightJobFileStoreProtocol = HighlightJobFileStore(),
        makeHighlightClip: @escaping MakeHighlightClip,
        saveVideo: @escaping (URL) async throws -> Void,
        assetForJobVideo: @escaping (HighlightJobVideo, HighlightClipAssetRequest) async throws -> AVAsset,
    ) {
        self.fileStore = fileStore
        self.makeHighlightClip = makeHighlightClip
        self.saveVideo = saveVideo
        self.assetForJobVideo = assetForJobVideo
    }

    @MainActor
    func run(
        job originalJob: HighlightJob,
        onChange: @escaping @MainActor (HighlightJob) -> Void,
    ) async throws -> HighlightJob {
        var job = originalJob
        job.status = .running
        job.progress = .zero
        job.errorMessage = nil
        job.updatedAt = Date()
        onChange(job)

        let selectedVideos = job.selectedVideos.map(\.selectedTrainingVideo)
        let plan = VideoClipSegmentPlanner.highlightPlan(
            for: job.trainingSession,
            videos: selectedVideos,
            clipSettings: job.clipSettings,
        )
        guard plan.canGenerate else {
            job.status = .failed
            job.errorMessage = "所选视频没有覆盖任何打点。"
            job.updatedAt = Date()
            onChange(job)
            return job
        }

        let videosByID = Dictionary(uniqueKeysWithValues: job.selectedVideos.map { ($0.id, $0) })

        do {
            try Task.checkCancellation()
            let temporaryOutputURL = try await makeHighlightClip(
                plan.segments,
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
            job.status = .saving
            job.updatedAt = Date()
            onChange(job)

            let outputURL = try fileStore.url(forRelativePath: outputRelativePath)
            do {
                try await saveVideo(outputURL)
            } catch {
                job.status = .failed
                job.errorMessage = "视频已生成，但保存到相册失败。"
                job.updatedAt = Date()
                onChange(job)
                return job
            }

            job.status = .completed
            job.progress = HighlightJobProgress(
                completedMarkerCount: plan.matchedMarkerCount,
                totalMarkerCount: plan.matchedMarkerCount,
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
    case sourceVideoMissing

    var errorDescription: String? {
        switch self {
        case .sourceVideoMissing:
            "找不到任务使用的视频，请重新选择视频。"
        }
    }
}

import Combine
import Foundation

@MainActor
final class HighlightJobManager: ObservableObject {
    @Published private(set) var jobs: [HighlightJob] = []

    private let store: HighlightJobStoreProtocol
    private let fileStore: HighlightJobFileStoreProtocol
    private let runnerFactory: (HighlightJob) -> HighlightJobRunner
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    init(
        store: HighlightJobStoreProtocol,
        fileStore: HighlightJobFileStoreProtocol,
        runnerFactory: @escaping (HighlightJob) -> HighlightJobRunner,
    ) {
        self.store = store
        self.fileStore = fileStore
        self.runnerFactory = runnerFactory
    }

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
    ) async throws -> HighlightJob {
        let now = Date()
        let jobID = UUID()
        let jobVideos = try selectedVideos.map { video in
            try makeJobVideo(from: video, jobID: jobID)
        }
        let job = HighlightJob(
            id: jobID,
            trainingSession: session,
            selectedVideos: jobVideos,
            clipSettings: clipSettings,
            status: .queued,
            progress: .zero,
            outputVideoPath: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now,
        )

        jobs.insert(job, at: 0)
        persist()
        startNextQueuedJobIfPossible()
        return job
    }

    func cancel(jobID: UUID) {
        runningTasks[jobID]?.cancel()
        runningTasks[jobID] = nil
        try? fileStore.removeAllFiles(for: jobID)
        jobs.removeAll { $0.id == jobID }
        persist()
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
        jobs[index].errorMessage = nil
        jobs[index].updatedAt = Date()
        persist()
        startNextQueuedJobIfPossible()
    }

    func clear(jobID: UUID) {
        runningTasks[jobID]?.cancel()
        runningTasks[jobID] = nil
        try? fileStore.removeAllFiles(for: jobID)
        jobs.removeAll { $0.id == jobID }
        persist()
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
                self.update(finalJob)
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

    private func persist() {
        try? store.saveJobs(jobs)
    }
}

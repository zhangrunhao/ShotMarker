import Foundation

protocol HighlightJobStoreProtocol {
    func loadJobs() throws -> [HighlightJob]
    func loadJobsForLaunchRecovery() throws -> [HighlightJob]
    func saveJobs(_ jobs: [HighlightJob]) throws
}

final class HighlightJobStore: HighlightJobStoreProtocol {
    private let fileURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadJobs() throws -> [HighlightJob] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([HighlightJob].self, from: data)
    }

    func loadJobsForLaunchRecovery() throws -> [HighlightJob] {
        try loadJobs().map { job in
            guard job.status.isLaunchInterruptedState else {
                return job
            }

            var interruptedJob = job
            interruptedJob.status = .interrupted
            interruptedJob.updatedAt = Date()
            return interruptedJob
        }
    }

    func saveJobs(_ jobs: [HighlightJob]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(jobs)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("ShotMarker", isDirectory: true)
            .appendingPathComponent("highlight-jobs.json")
    }
}

final class InMemoryHighlightJobStore: HighlightJobStoreProtocol {
    private var jobs: [HighlightJob]

    init(jobs: [HighlightJob] = []) {
        self.jobs = jobs
    }

    func loadJobs() throws -> [HighlightJob] {
        jobs
    }

    func loadJobsForLaunchRecovery() throws -> [HighlightJob] {
        jobs.map { job in
            guard job.status.isLaunchInterruptedState else {
                return job
            }

            var interruptedJob = job
            interruptedJob.status = .interrupted
            interruptedJob.updatedAt = Date()
            return interruptedJob
        }
    }

    func saveJobs(_ jobs: [HighlightJob]) throws {
        self.jobs = jobs
    }
}

import Foundation

protocol TrainingSessionStoreProtocol {
    func loadTrainingSessions() throws -> [TrainingSession]
    func saveTrainingSessions(_ sessions: [TrainingSession]) throws
}

final class TrainingSessionStore: TrainingSessionStoreProtocol {
    private let fileURL: URL
    private let fileManager: FileManager
    private let seedSessions: [TrainingSession]
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(fileURL: URL? = nil, fileManager: FileManager = .default, seedSessions: [TrainingSession] = []) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.seedSessions = seedSessions
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadTrainingSessions() throws -> [TrainingSession] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            if !seedSessions.isEmpty {
                try saveTrainingSessions(seedSessions)
                return seedSessions
            }

            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([TrainingSession].self, from: data)
    }

    func saveTrainingSessions(_ sessions: [TrainingSession]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("ShotMarker", isDirectory: true)
            .appendingPathComponent("training-sessions.json")
    }
}

final class InMemoryTrainingSessionStore: TrainingSessionStoreProtocol {
    private var sessions: [TrainingSession]

    init(sessions: [TrainingSession]) {
        self.sessions = sessions
    }

    func loadTrainingSessions() throws -> [TrainingSession] {
        sessions
    }

    func saveTrainingSessions(_ sessions: [TrainingSession]) throws {
        self.sessions = sessions
    }
}

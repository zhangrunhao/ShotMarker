import Foundation

enum WatchTrainingSyncOutboxEntryStatus: String, Codable, Equatable {
    case pendingTransfer
    case awaitingAck
}

struct WatchTrainingSyncOutboxEntry: Codable, Equatable {
    let payload: TrainingSessionSyncPayload
    var status: WatchTrainingSyncOutboxEntryStatus
    var lastTransferFinishedAt: Date?

    init(
        payload: TrainingSessionSyncPayload,
        status: WatchTrainingSyncOutboxEntryStatus,
        lastTransferFinishedAt: Date? = nil,
    ) {
        self.payload = payload
        self.status = status
        self.lastTransferFinishedAt = lastTransferFinishedAt
    }
}

final class WatchTrainingSyncOutbox {
    private let fileURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        fileURL: URL = WatchTrainingSyncOutbox.defaultFileURL(),
        fileManager: FileManager = .default,
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadEntries() throws -> [WatchTrainingSyncOutboxEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([WatchTrainingSyncOutboxEntry].self, from: data)
    }

    func enqueue(_ payload: TrainingSessionSyncPayload) throws {
        var entries = try loadEntries()
        entries.removeAll { $0.payload.id == payload.id }
        entries.append(WatchTrainingSyncOutboxEntry(payload: payload, status: .pendingTransfer))
        try save(entries)
    }

    func markAwaitingAck(trainingSessionId: UUID, lastTransferFinishedAt: Date) throws {
        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.payload.id == trainingSessionId }) else {
            return
        }

        entries[index].status = .awaitingAck
        entries[index].lastTransferFinishedAt = lastTransferFinishedAt
        try save(entries)
    }

    func markPendingTransfer(trainingSessionId: UUID) throws {
        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.payload.id == trainingSessionId }) else {
            return
        }

        entries[index].status = .pendingTransfer
        entries[index].lastTransferFinishedAt = nil
        try save(entries)
    }

    func remove(trainingSessionId: UUID) throws {
        var entries = try loadEntries()
        entries.removeAll { $0.payload.id == trainingSessionId }
        try save(entries)
    }

    private func save(_ entries: [WatchTrainingSyncOutboxEntry]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL() -> URL {
        let directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directoryURL.appendingPathComponent("watch-training-sync-outbox.json")
    }
}

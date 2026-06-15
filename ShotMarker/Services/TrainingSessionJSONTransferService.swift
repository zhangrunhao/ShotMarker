import Foundation

struct TrainingSessionJSONImportResult: Equatable {
    let importedCount: Int
    let insertedCount: Int
    let replacedCount: Int
}

enum TrainingSessionJSONTransferError: LocalizedError, Equatable {
    case emptyExportSelection
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .emptyExportSelection:
            "请先选择要导出的训练记录。"
        case .invalidJSON:
            "JSON 文件格式不正确，无法导入训练记录。"
        }
    }
}

struct TrainingSessionJSONTransferService {
    private let store: TrainingSessionStoreProtocol
    private let notificationCenter: NotificationCenter
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init(
        store: TrainingSessionStoreProtocol,
        notificationCenter: NotificationCenter = .default,
    ) {
        self.store = store
        self.notificationCenter = notificationCenter

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func importTrainingSessions(from fileURL: URL) throws -> TrainingSessionJSONImportResult {
        let isAccessingSecurityScopedResource = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessingSecurityScopedResource {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        return try importTrainingSessions(from: Data(contentsOf: fileURL))
    }

    func importTrainingSessions(from data: Data) throws -> TrainingSessionJSONImportResult {
        guard let importedSessions = Self.decodeTrainingSessions(from: data, decoder: decoder) else {
            throw TrainingSessionJSONTransferError.invalidJSON
        }

        var sessions = try store.loadTrainingSessions()
        var insertedCount = 0
        var replacedCount = 0

        for importedSession in importedSessions {
            if let index = sessions.firstIndex(where: { $0.id == importedSession.id }) {
                sessions[index] = importedSession
                replacedCount += 1
            } else {
                sessions.append(importedSession)
                insertedCount += 1
            }
        }

        try store.saveTrainingSessions(sessions)
        notificationCenter.post(name: .trainingSessionsDidChange, object: nil)

        return TrainingSessionJSONImportResult(
            importedCount: importedSessions.count,
            insertedCount: insertedCount,
            replacedCount: replacedCount,
        )
    }

    func exportData(for sessions: [TrainingSession]) throws -> Data {
        guard !sessions.isEmpty else {
            throw TrainingSessionJSONTransferError.emptyExportSelection
        }

        return try encoder.encode(sessions)
    }

    private static func decodeTrainingSessions(from data: Data, decoder: JSONDecoder) -> [TrainingSession]? {
        if let sessions = try? decoder.decode([TrainingSession].self, from: data) {
            return sessions
        }

        if let session = try? decoder.decode(TrainingSession.self, from: data) {
            return [session]
        }

        return nil
    }
}

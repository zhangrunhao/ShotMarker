import Foundation

protocol TimestampFileStoreProtocol {
    func loadTimestampFiles() throws -> [TimestampFile]
    func saveTimestampFiles(_ files: [TimestampFile]) throws
}

final class TimestampFileStore: TimestampFileStoreProtocol {
    private let fileURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadTimestampFiles() throws -> [TimestampFile] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([TimestampFile].self, from: data)
    }

    func saveTimestampFiles(_ files: [TimestampFile]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(files)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("ShotMarker", isDirectory: true)
            .appendingPathComponent("timestamp-files.json")
    }
}

final class InMemoryTimestampFileStore: TimestampFileStoreProtocol {
    private var files: [TimestampFile]

    init(files: [TimestampFile]) {
        self.files = files
    }

    func loadTimestampFiles() throws -> [TimestampFile] {
        files
    }

    func saveTimestampFiles(_ files: [TimestampFile]) throws {
        self.files = files
    }
}

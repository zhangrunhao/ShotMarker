import Foundation

actor AppLogStore {
    struct Configuration: Equatable, Sendable {
        var retentionDays: Int = 14
        var maxTotalBytes: Int = 30 * 1024 * 1024
    }

    private let directoryURL: URL
    nonisolated let configuration: Configuration
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryURL: URL = AppLogStore.defaultDirectoryURL(),
        configuration: Configuration = Configuration(),
        calendar: Calendar = .current,
        now: @Sendable @escaping () -> Date = Date.init,
    ) {
        self.directoryURL = directoryURL
        self.configuration = configuration
        self.calendar = calendar
        self.now = now

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func append(_ event: AppLogEvent) async {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var data = try encoder.encode(event)
            data.append(Data("\n".utf8))
            try append(data, to: logFileURL(for: event.timestamp))
        } catch {
            return
        }
    }

    func readAll() async -> [AppLogEvent] {
        do {
            return try logFileURLs()
                .flatMap(readEvents)
                .sorted { lhs, rhs in lhs.timestamp < rhs.timestamp }
        } catch {
            return []
        }
    }

    func cleanup() async {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try deleteFilesOlderThanRetentionWindow()
            try enforceMaximumTotalSize()
        } catch {
            return
        }
    }

    static func defaultDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private func append(_ data: Data, to fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            try data.write(to: fileURL, options: [.atomic])
            return
        }

        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? fileHandle.close()
        }
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: data)
    }

    private func readEvents(from fileURL: URL) throws -> [AppLogEvent] {
        let data = try Data(contentsOf: fileURL)
        guard let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        return contents
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(AppLogEvent.self, from: Data(line.utf8))
            }
    }

    private func deleteFilesOlderThanRetentionWindow() throws {
        let startOfToday = calendar.startOfDay(for: now())
        guard let cutoffDate = calendar.date(byAdding: .day, value: -configuration.retentionDays, to: startOfToday) else {
            return
        }

        for entry in try logFileEntries() where entry.date < cutoffDate {
            try fileManager.removeItem(at: entry.url)
        }
    }

    private func enforceMaximumTotalSize() throws {
        let entries = try logFileEntries()
        var totalBytes = entries.reduce(0) { $0 + $1.size }

        for entry in entries.sorted(by: { $0.date < $1.date }) where totalBytes > configuration.maxTotalBytes {
            try fileManager.removeItem(at: entry.url)
            totalBytes -= entry.size
        }
    }

    private func logFileURL(for date: Date) -> URL {
        directoryURL.appendingPathComponent(logFilename(for: date), isDirectory: false)
    }

    private func logFilename(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "phone-%04d-%02d-%02d.jsonl",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
        )
    }

    private func logFileURLs() throws -> [URL] {
        try logFileEntries().map(\.url)
    }

    private func logFileEntries() throws -> [LogFileEntry] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
        )
        .compactMap { fileURL -> LogFileEntry? in
            guard let date = logDate(from: fileURL.lastPathComponent) else {
                return nil
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resourceValues?.isRegularFile == true else {
                return nil
            }

            return LogFileEntry(url: fileURL, date: date, size: resourceValues?.fileSize ?? 0)
        }
        .sorted { lhs, rhs in lhs.date < rhs.date }
    }

    private func logDate(from filename: String) -> Date? {
        guard filename.hasPrefix("phone-"), filename.hasSuffix(".jsonl") else {
            return nil
        }

        let dateString = filename
            .dropFirst("phone-".count)
            .dropLast(".jsonl".count)
        let parts = dateString.split(separator: "-").compactMap { Int(String($0)) }
        guard parts.count == 3 else {
            return nil
        }

        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
        ))
    }
}

private struct LogFileEntry {
    let url: URL
    let date: Date
    let size: Int
}

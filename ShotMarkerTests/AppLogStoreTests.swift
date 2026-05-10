@testable import ShotMarker
import XCTest

final class AppLogStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        calendar = nil
    }

    func testAppendWritesOneJSONLineIntoDailyLogFile() async throws {
        let now = fixedDate(year: 2026, month: 5, day: 10, hour: 11)
        let store = AppLogStore(directoryURL: temporaryDirectory, calendar: calendar, now: { now })
        let event = makeEvent(timestamp: now, name: "app.launch")

        await store.append(event)

        let fileURL = temporaryDirectory.appendingPathComponent("phone-2026-05-10.jsonl")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(try logDecoder().decode(AppLogEvent.self, from: Data(lines[0].utf8)), event)
    }

    func testReadAllReturnsEventsInTimestampOrder() async throws {
        let store = AppLogStore(directoryURL: temporaryDirectory, calendar: calendar)
        let laterEvent = makeEvent(
            id: "00000000-0000-0000-0000-000000000202",
            timestamp: fixedDate(year: 2026, month: 5, day: 10, hour: 12),
            name: "sync.training.import.succeeded",
        )
        let earlierEvent = makeEvent(
            id: "00000000-0000-0000-0000-000000000201",
            timestamp: fixedDate(year: 2026, month: 5, day: 9, hour: 12),
            name: "app.launch",
        )

        try writeEvents([laterEvent], to: "phone-2026-05-10.jsonl")
        try writeEvents([earlierEvent], to: "phone-2026-05-09.jsonl")

        let events = await store.readAll()

        XCTAssertEqual(events, [earlierEvent, laterEvent])
    }

    func testCleanupDeletesFilesOlderThanRetentionWindow() async throws {
        let now = fixedDate(year: 2026, month: 5, day: 10)
        let store = AppLogStore(
            directoryURL: temporaryDirectory,
            configuration: AppLogStore.Configuration(retentionDays: 14, maxTotalBytes: 30 * 1024 * 1024),
            calendar: calendar,
            now: { now },
        )
        try writeText("old\n", to: "phone-2026-04-25.jsonl")
        try writeText("kept\n", to: "phone-2026-04-26.jsonl")
        try writeText("current\n", to: "phone-2026-05-10.jsonl")

        await store.cleanup()

        XCTAssertFalse(fileExists("phone-2026-04-25.jsonl"))
        XCTAssertTrue(fileExists("phone-2026-04-26.jsonl"))
        XCTAssertTrue(fileExists("phone-2026-05-10.jsonl"))
    }

    func testCleanupDeletesOldestFilesWhenTotalSizeExceedsLimit() async throws {
        let store = AppLogStore(
            directoryURL: temporaryDirectory,
            configuration: AppLogStore.Configuration(retentionDays: 14, maxTotalBytes: 10),
            calendar: calendar,
            now: { self.fixedDate(year: 2026, month: 5, day: 10) },
        )
        try writeText("12345", to: "phone-2026-05-08.jsonl")
        try writeText("1234", to: "phone-2026-05-09.jsonl")
        try writeText("1234", to: "phone-2026-05-10.jsonl")

        await store.cleanup()

        XCTAssertFalse(fileExists("phone-2026-05-08.jsonl"))
        XCTAssertTrue(fileExists("phone-2026-05-09.jsonl"))
        XCTAssertTrue(fileExists("phone-2026-05-10.jsonl"))
    }

    func testReadAllSkipsCorruptedLines() async throws {
        let store = AppLogStore(directoryURL: temporaryDirectory, calendar: calendar)
        let firstEvent = makeEvent(
            id: "00000000-0000-0000-0000-000000000301",
            timestamp: fixedDate(year: 2026, month: 5, day: 10, hour: 10),
            name: "diagnostics.export.started",
        )
        let secondEvent = makeEvent(
            id: "00000000-0000-0000-0000-000000000302",
            timestamp: fixedDate(year: 2026, month: 5, day: 10, hour: 11),
            name: "diagnostics.export.failed",
        )
        let encoder = logEncoder()
        let validLine1 = String(decoding: try encoder.encode(firstEvent), as: UTF8.self)
        let validLine2 = String(decoding: try encoder.encode(secondEvent), as: UTF8.self)
        try writeText("\(validLine1)\nnot-json\n\(validLine2)\n", to: "phone-2026-05-10.jsonl")

        let events = await store.readAll()

        XCTAssertEqual(events, [firstEvent, secondEvent])
    }

    private func makeEvent(
        id: String = "00000000-0000-0000-0000-000000000200",
        timestamp: Date,
        name: String,
    ) -> AppLogEvent {
        AppLogEvent(
            id: UUID(uuidString: id)!,
            timestamp: timestamp,
            level: .info,
            category: .app,
            name: name,
            message: "测试日志",
            context: ["source": "test"],
            errorDomain: nil,
            errorCode: nil,
            errorDescription: nil,
        )
    }

    private func fixedDate(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour).date!
    }

    private func writeEvents(_ events: [AppLogEvent], to filename: String) throws {
        let encoder = logEncoder()
        let lines = try events.map { event in
            String(decoding: try encoder.encode(event), as: UTF8.self)
        }
        try writeText(lines.joined(separator: "\n") + "\n", to: filename)
    }

    private func writeText(_ text: String, to filename: String) throws {
        let fileURL = temporaryDirectory.appendingPathComponent(filename)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func logEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func logDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func fileExists(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent(filename).path)
    }
}

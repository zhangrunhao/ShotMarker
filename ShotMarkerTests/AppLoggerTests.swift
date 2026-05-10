@testable import ShotMarker
import XCTest

final class AppLoggerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testInfoWritesInfoLogAsynchronously() async throws {
        let store = AppLogStore(directoryURL: temporaryDirectory)
        let logger = AppLogger(store: store)

        logger.info(
            "diagnostics.export.started",
            category: .diagnostics,
            message: "开始导出诊断日志",
            context: ["retentionDays": "14"],
        )

        let events = await eventuallyReadEvents(from: store, expectedCount: 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.category, .diagnostics)
        XCTAssertEqual(event.name, "diagnostics.export.started")
        XCTAssertEqual(event.message, "开始导出诊断日志")
    }

    func testErrorWritesErrorMetadata() async throws {
        let store = AppLogStore(directoryURL: temporaryDirectory)
        let logger = AppLogger(store: store)
        let error = NSError(
            domain: "ShotMarkerLoggerTests",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Export failed"],
        )

        logger.error(
            "diagnostics.export.failed",
            category: .diagnostics,
            message: "诊断日志导出失败",
            error: error,
            context: [:],
        )

        let events = await eventuallyReadEvents(from: store, expectedCount: 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.level, .error)
        XCTAssertEqual(event.errorDomain, "ShotMarkerLoggerTests")
        XCTAssertEqual(event.errorCode, 500)
        XCTAssertEqual(event.errorDescription, "Export failed")
    }

    func testContextFieldsAreStored() async throws {
        let store = AppLogStore(directoryURL: temporaryDirectory)
        let logger = AppLogger(store: store)

        logger.info(
            "highlight.generate.started",
            category: .video,
            message: "开始生成集锦",
            context: [
                "matchedMarkerCount": "9",
                "selectedVideoCount": "1",
                "trainingSessionId": "session-1",
            ],
        )

        let events = await eventuallyReadEvents(from: store, expectedCount: 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.context["matchedMarkerCount"], "9")
        XCTAssertEqual(event.context["selectedVideoCount"], "1")
        XCTAssertEqual(event.context["trainingSessionId"], "session-1")
    }

    private func eventuallyReadEvents(from store: AppLogStore, expectedCount: Int) async -> [AppLogEvent] {
        for _ in 0..<50 {
            let events = await store.readAll()
            if events.count >= expectedCount {
                return events
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Expected at least \(expectedCount) app log events")
        return await store.readAll()
    }
}

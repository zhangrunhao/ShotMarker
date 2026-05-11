@testable import ShotMarker
import XCTest

final class AppLogExportServiceTests: XCTestCase {
    private var logDirectory: URL!
    private var exportDirectory: URL!
    private var calendar: Calendar!
    private var exportDate: Date!

    override func setUpWithError() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        logDirectory = rootDirectory.appendingPathComponent("logs", isDirectory: true)
        exportDirectory = rootDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        exportDate = fixedDate(year: 2026, month: 5, day: 10, hour: 11, minute: 35)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: logDirectory.deletingLastPathComponent())
        logDirectory = nil
        exportDirectory = nil
        calendar = nil
        exportDate = nil
    }

    func testExportWritesDecodableDiagnosticsFile() async throws {
        let event = makeEvent(
            id: "00000000-0000-0000-0000-000000000401",
            timestamp: fixedDate(year: 2026, month: 5, day: 10, hour: 11),
            name: "diagnostics.export.started",
        )
        let store = AppLogStore(directoryURL: logDirectory, calendar: calendar)
        await store.append(event)
        let service = makeService(store: store)

        let fileURL = try await service.export()
        let bundle = try decodeBundle(at: fileURL)

        XCTAssertEqual(fileURL.lastPathComponent, "ShotMarker-Diagnostics-20260510-113500.json")
        XCTAssertEqual(bundle.manifest.schemaVersion, 1)
        XCTAssertEqual(bundle.manifest.exportedAt, exportDate)
        XCTAssertEqual(bundle.manifest.appVersion, "1.2.3")
        XCTAssertEqual(bundle.manifest.buildNumber, "456")
        XCTAssertEqual(bundle.manifest.platform, "iOS")
        XCTAssertEqual(bundle.manifest.systemVersion, "26.4")
        XCTAssertEqual(bundle.manifest.deviceModel, "iPhone")
        XCTAssertEqual(bundle.manifest.retentionDays, 14)
        XCTAssertEqual(bundle.manifest.maxLogBytes, 30 * 1024 * 1024)
        XCTAssertNil(bundle.phoneDiagnostics)
        XCTAssertEqual(bundle.watchDiagnostics, WatchDiagnosticsExport(included: false, reason: "watch logs are planned for P1"))
        XCTAssertEqual(bundle.logs, [event])
    }

    func testExportIncludesPhoneWatchSyncDiagnosticsSnapshot() async throws {
        let store = AppLogStore(directoryURL: logDirectory, calendar: calendar)
        let snapshot = PhoneWatchSyncDiagnosticsSnapshot(
            isSupported: true,
            isPaired: true,
            isWatchAppInstalled: false,
            activationState: "activated",
            lastActivationCompletedAt: fixedDate(year: 2026, month: 5, day: 10, hour: 10),
            lastActivationErrorDescription: nil,
            lastReceivedPayloadAt: fixedDate(year: 2026, month: 5, day: 10, hour: 11),
            lastReceivedTrainingSessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000501"),
            lastImportErrorDescription: "import failed",
            lastAckSentAt: fixedDate(year: 2026, month: 5, day: 10, hour: 12),
            lastAckTrainingSessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000502"),
            lastAckErrorDescription: "ack failed",
        )
        let service = makeService(store: store, diagnosticsSnapshotProvider: { snapshot })

        let fileURL = try await service.export()
        let phoneDiagnostics = try XCTUnwrap(decodeBundle(at: fileURL).phoneDiagnostics)

        XCTAssertEqual(phoneDiagnostics.watchConnectivity.isSupported, true)
        XCTAssertEqual(phoneDiagnostics.watchConnectivity.isPaired, true)
        XCTAssertEqual(phoneDiagnostics.watchConnectivity.isWatchAppInstalled, false)
        XCTAssertEqual(phoneDiagnostics.watchConnectivity.activationState, "activated")
        XCTAssertEqual(phoneDiagnostics.lastReceivedTrainingSessionId, snapshot.lastReceivedTrainingSessionId)
        XCTAssertEqual(phoneDiagnostics.lastImportErrorDescription, "import failed")
        XCTAssertEqual(phoneDiagnostics.lastAckTrainingSessionId, snapshot.lastAckTrainingSessionId)
        XCTAssertEqual(phoneDiagnostics.lastAckErrorDescription, "ack failed")
    }

    func testExportRunsLogCleanupBeforeReadingEvents() async throws {
        let oldEvent = makeEvent(
            id: "00000000-0000-0000-0000-000000000601",
            timestamp: fixedDate(year: 2026, month: 5, day: 8),
            name: "old.event",
        )
        let retainedEvent = makeEvent(
            id: "00000000-0000-0000-0000-000000000602",
            timestamp: fixedDate(year: 2026, month: 5, day: 10),
            name: "retained.event",
        )
        let cleanupNow = fixedDate(year: 2026, month: 5, day: 10)
        let store = AppLogStore(
            directoryURL: logDirectory,
            configuration: AppLogStore.Configuration(retentionDays: 1, maxTotalBytes: 30 * 1024 * 1024),
            calendar: calendar,
            now: { cleanupNow },
        )
        await store.append(oldEvent)
        await store.append(retainedEvent)
        let service = makeService(store: store)

        let fileURL = try await service.export()

        XCTAssertEqual(try decodeBundle(at: fileURL).logs, [retainedEvent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: logDirectory.appendingPathComponent("phone-2026-05-08.jsonl").path))
    }

    private func makeService(
        store: AppLogStore,
        diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)? = nil,
    ) -> AppLogExportService {
        AppLogExportService(
            store: store,
            diagnosticsSnapshotProvider: diagnosticsSnapshotProvider,
            outputDirectoryURL: exportDirectory,
            calendar: calendar,
            now: { self.exportDate },
            appInfoProvider: { AppLogExportAppInfo(appVersion: "1.2.3", buildNumber: "456") },
            deviceInfoProvider: { AppLogExportDeviceInfo(platform: "iOS", systemVersion: "26.4", deviceModel: "iPhone") },
        )
    }

    private func decodeBundle(at fileURL: URL) throws -> AppLogExportBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppLogExportBundle.self, from: Data(contentsOf: fileURL))
    }

    private func makeEvent(id: String, timestamp: Date, name: String) -> AppLogEvent {
        AppLogEvent(
            id: UUID(uuidString: id)!,
            timestamp: timestamp,
            level: .info,
            category: .diagnostics,
            name: name,
            message: "测试日志",
            context: [:],
            errorDomain: nil,
            errorCode: nil,
            errorDescription: nil,
        )
    }

    private func fixedDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
        ).date!
    }
}

import Foundation

#if canImport(UIKit)
    import UIKit
#endif

nonisolated struct AppLogExportAppInfo: Equatable, Sendable {
    let appVersion: String
    let buildNumber: String

    static func current(bundle: Bundle = .main) -> AppLogExportAppInfo {
        AppLogExportAppInfo(
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
        )
    }
}

nonisolated struct AppLogExportDeviceInfo: Equatable, Sendable {
    let platform: String
    let systemVersion: String
    let deviceModel: String

    @MainActor
    static func current() -> AppLogExportDeviceInfo {
        #if canImport(UIKit)
            AppLogExportDeviceInfo(
                platform: "iOS",
                systemVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.current.model,
            )
        #else
            AppLogExportDeviceInfo(platform: "unknown", systemVersion: "unknown", deviceModel: "unknown")
        #endif
    }
}

nonisolated struct AppLogExportManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let buildNumber: String
    let platform: String
    let systemVersion: String
    let deviceModel: String
    let retentionDays: Int
    let maxLogBytes: Int
}

nonisolated struct PhoneWatchConnectivityDiagnosticsExport: Codable, Equatable, Sendable {
    let isSupported: Bool
    let isPaired: Bool
    let isWatchAppInstalled: Bool
    let activationState: String
}

nonisolated struct PhoneWatchSyncDiagnosticsExport: Codable, Equatable, Sendable {
    let watchConnectivity: PhoneWatchConnectivityDiagnosticsExport
    let lastActivationCompletedAt: Date?
    let lastActivationErrorDescription: String?
    let lastReceivedPayloadAt: Date?
    let lastReceivedTrainingSessionId: UUID?
    let lastImportErrorDescription: String?
    let lastAckSentAt: Date?
    let lastAckTrainingSessionId: UUID?
    let lastAckErrorDescription: String?

    init(snapshot: PhoneWatchSyncDiagnosticsSnapshot) {
        watchConnectivity = PhoneWatchConnectivityDiagnosticsExport(
            isSupported: snapshot.isSupported,
            isPaired: snapshot.isPaired,
            isWatchAppInstalled: snapshot.isWatchAppInstalled,
            activationState: snapshot.activationState,
        )
        lastActivationCompletedAt = snapshot.lastActivationCompletedAt
        lastActivationErrorDescription = snapshot.lastActivationErrorDescription
        lastReceivedPayloadAt = snapshot.lastReceivedPayloadAt
        lastReceivedTrainingSessionId = snapshot.lastReceivedTrainingSessionId
        lastImportErrorDescription = snapshot.lastImportErrorDescription
        lastAckSentAt = snapshot.lastAckSentAt
        lastAckTrainingSessionId = snapshot.lastAckTrainingSessionId
        lastAckErrorDescription = snapshot.lastAckErrorDescription
    }
}

nonisolated struct WatchDiagnosticsExport: Codable, Equatable, Sendable {
    let included: Bool
    let reason: String
}

nonisolated struct AppLogExportBundle: Codable, Equatable, Sendable {
    let manifest: AppLogExportManifest
    let phoneDiagnostics: PhoneWatchSyncDiagnosticsExport?
    let watchDiagnostics: WatchDiagnosticsExport
    let logs: [AppLogEvent]
}

nonisolated struct AppLogExportService {
    let store: AppLogStore
    let diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)?

    private let outputDirectoryURL: URL
    private let calendar: Calendar
    private let now: () -> Date
    private let appInfoProvider: () -> AppLogExportAppInfo
    private let deviceInfoProvider: @MainActor () -> AppLogExportDeviceInfo
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(
        store: AppLogStore,
        diagnosticsSnapshotProvider: (() -> PhoneWatchSyncDiagnosticsSnapshot)? = nil,
        outputDirectoryURL: URL = FileManager.default.temporaryDirectory,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        appInfoProvider: @escaping () -> AppLogExportAppInfo = { AppLogExportAppInfo.current() },
        deviceInfoProvider: @MainActor @escaping () -> AppLogExportDeviceInfo = { AppLogExportDeviceInfo.current() },
        fileManager: FileManager = .default,
    ) {
        self.store = store
        self.diagnosticsSnapshotProvider = diagnosticsSnapshotProvider
        self.outputDirectoryURL = outputDirectoryURL
        self.calendar = calendar
        self.now = now
        self.appInfoProvider = appInfoProvider
        self.deviceInfoProvider = deviceInfoProvider
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func export() async throws -> URL {
        await store.cleanup()

        let exportedAt = now()
        let logs = await store.readAll()
        let bundle = AppLogExportBundle(
            manifest: await makeManifest(exportedAt: exportedAt),
            phoneDiagnostics: diagnosticsSnapshotProvider.map { PhoneWatchSyncDiagnosticsExport(snapshot: $0()) },
            watchDiagnostics: WatchDiagnosticsExport(included: false, reason: "watch logs are planned for P1"),
            logs: logs,
        )
        let fileURL = outputDirectoryURL.appendingPathComponent(filename(for: exportedAt), isDirectory: false)
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        try encoder.encode(bundle).write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private func makeManifest(exportedAt: Date) async -> AppLogExportManifest {
        let appInfo = appInfoProvider()
        let deviceInfo = await deviceInfoProvider()
        return AppLogExportManifest(
            schemaVersion: 1,
            exportedAt: exportedAt,
            appVersion: appInfo.appVersion,
            buildNumber: appInfo.buildNumber,
            platform: deviceInfo.platform,
            systemVersion: deviceInfo.systemVersion,
            deviceModel: deviceInfo.deviceModel,
            retentionDays: store.configuration.retentionDays,
            maxLogBytes: store.configuration.maxTotalBytes,
        )
    }

    private func filename(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "山药蛋-Diagnostics-%04d%02d%02d-%02d%02d%02d.json",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
        )
    }
}

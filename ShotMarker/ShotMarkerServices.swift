import Foundation
import UIKit

@MainActor
final class ShotMarkerServices: ShotMarkerServiceLifecycle {
    let store: TrainingSessionStore
    let syncService: PhoneWatchSyncService
    let logger: AppLogging
    let logExportService: AppLogExportService
    let highlightTaskManager: HighlightTaskManager
    private let analytics: AnalyticsTracking

    init(dataCutoverAt: Date?) {
        // This initializer is reachable only after the epoch transaction succeeds.
        GlitchTipCrashReporter.start()
        store = TrainingSessionStore()
        logger = AppLogger.shared
        #if DEBUG
            let isDebugBuild = true
        #else
            let isDebugBuild = false
        #endif
        analytics = AnalyticsRuntimePolicy.shouldSend(isDebugBuild: isDebugBuild,
            isPhone: UIDevice.current.userInterfaceIdiom == .phone) ? AnalyticsClient.live() : NoopAnalyticsTracker()
        syncService = PhoneWatchSyncService(importer: TrainingSessionImporter(store: store, logger: logger),
            logger: logger, analytics: analytics, dataCutoverAt: dataCutoverAt)
        logExportService = AppLogExportService(store: AppLogStore.shared,
            diagnosticsSnapshotProvider: syncService.diagnosticsSnapshot)
        highlightTaskManager = .live(logger: logger, analytics: analytics)
    }

    func load() async {
        await highlightTaskManager.load()
    }

    func enterBackground() { highlightTaskManager.enterBackground() }
    func enterForeground() { highlightTaskManager.enterForeground() }

    func start() {
        logger.info("app.launch", category: .app, message: "应用启动")
        analytics.track(.appLaunch)
        syncService.start()
    }
}

//
//  ShotMarkerApp.swift
//  ShotMarker
//
//  Created by runhao zhang on 2026/5/1.
//

import SwiftUI
#if os(iOS)
    import UIKit
#endif

@main
struct ShotMarkerApp: App {
    private let store: TrainingSessionStore
    private let syncService: PhoneWatchSyncService
    private let logger: AppLogging
    private let logExportService: AppLogExportService
    #if os(iOS)
        @StateObject private var highlightJobManager: HighlightJobManager
    #endif

    @MainActor
    init() {
        #if os(iOS)
            GlitchTipCrashReporter.start()
        #endif

        #if DEBUG
            let store = TrainingSessionStore(seedSessions: TrainingSession.previewSessions)
        #else
            let store = TrainingSessionStore()
        #endif
        let logStore = AppLogStore.shared
        let logger = AppLogger.shared
        #if DEBUG
            let isDebugBuild = true
        #else
            let isDebugBuild = false
        #endif
        #if os(iOS)
            let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        #else
            let isPhone = false
        #endif

        let analytics: AnalyticsTracking
        if AnalyticsRuntimePolicy.shouldSend(
            isDebugBuild: isDebugBuild,
            isPhone: isPhone,
        ) {
            analytics = AnalyticsClient.live()
        } else {
            analytics = NoopAnalyticsTracker()
        }
        let syncService = PhoneWatchSyncService(
            importer: TrainingSessionImporter(store: store),
            logger: logger,
            analytics: analytics,
        )
        let logExportService = AppLogExportService(
            store: logStore,
            diagnosticsSnapshotProvider: syncService.diagnosticsSnapshot,
        )
        #if os(iOS)
            let highlightJobManager = HighlightJobManager.live(
                logger: logger,
                analytics: analytics,
            )
            _highlightJobManager = StateObject(wrappedValue: highlightJobManager)
            highlightJobManager.load()
        #endif

        self.store = store
        self.syncService = syncService
        self.logger = logger
        self.logExportService = logExportService
        logger.info(
            "app.launch",
            category: .app,
            message: "应用启动",
        )
        analytics.track(.appLaunch)
        syncService.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                syncService: syncService,
                logger: logger,
                logExportService: logExportService,
                highlightJobManager: highlightJobManager,
            )
        }
    }
}

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
        private let reviewStore: any HighlightClipReviewStoring
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
        let reviewStore = FileHighlightClipReviewStore()
        let syncService = PhoneWatchSyncService(
            importer: TrainingSessionImporter(
                store: store,
                reviewStore: reviewStore,
                logger: logger,
            ),
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
            self.reviewStore = reviewStore
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
            #if DEBUG
                if ProcessInfo.processInfo.environment["SHOTMARKER_UI_TEST_TIMELINE"] == "1" {
                    HighlightClipTimelineUITestHarnessView()
                } else if ProcessInfo.processInfo.environment[
                    "SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"
                ] == "1" {
                    HighlightClipConfirmationUITestHarnessView()
                } else {
                    contentView
                }
            #else
                contentView
            #endif
        }
    }

    private var contentView: some View {
        ContentView(
            store: store,
            syncService: syncService,
            logger: logger,
            logExportService: logExportService,
            highlightJobManager: highlightJobManager,
            reviewStore: reviewStore,
        )
    }
}

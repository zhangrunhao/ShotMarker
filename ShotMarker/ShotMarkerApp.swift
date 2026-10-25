import Combine
import SwiftUI
import UIKit

@main
struct ShotMarkerApp: App {
    @StateObject private var bootstrap = ShotMarkerBootstrap<ShotMarkerServices>()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ProcessInfo.processInfo.environment["SHOTMARKER_UI_TEST_TIMELINE"] == "1" {
                    HighlightClipTimelineUITestHarnessView()
                } else if ProcessInfo.processInfo.environment["SHOTMARKER_UI_TEST_CLIP_CONFIRMATION"] == "1" {
                    HighlightClipConfirmationUITestHarnessView()
                } else if ProcessInfo.processInfo.environment["SHOTMARKER_UI_TEST_TASK_STATE"] != nil {
                    HighlightTaskUITestHarnessView()
                } else {
                    content
                }
            #else
                content
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            bootstrap.updateScenePhase(phase)
        }
    }

    private var content: some View {
        Group {
            if let services = bootstrap.services {
                ContentView(store: services.store, syncService: services.syncService,
                    logger: services.logger, logExportService: services.logExportService,
                    highlightTaskManager: services.highlightTaskManager)
            } else if bootstrap.resetFailed {
                ContentUnavailableView {
                    Label("无法完成数据升级", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("本地数据升级尚未完成。请检查可用空间后重试。")
                } actions: {
                    Button("重试") { Task { await bootstrap.start() } }
                }
            } else { ProgressView("正在准备本地数据…") }
        }
        .task {
            bootstrap.updateScenePhase(scenePhase)
            await bootstrap.start()
        }
    }
}

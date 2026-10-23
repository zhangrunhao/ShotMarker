#if DEBUG
import Foundation
import AVFoundation
import SwiftUI

/// Isolated, deterministic state fixtures for the real task row and configuration views.
struct HighlightTaskUITestHarnessView: View {
    @StateObject private var fixture = TaskUIFixture()
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(fixture.manager.tasks) { task in
                    HighlightTaskRow(task: task, manager: fixture.manager,
                        onEdit: { editing = true }, onPlay: {})
                }
            }
            .navigationDestination(isPresented: $editing) {
                if let task = fixture.manager.tasks.first {
                    HighlightTaskEditorView(task: task, manager: fixture.manager) { editing = false }
                }
            }
            .task { await fixture.prepare() }
        }
    }
}

@MainActor
private final class TaskUIFixture: ObservableObject {
    let manager: HighlightTaskManager
    private let store: HighlightTaskStore
    private let files: HighlightTaskFileStore
    private let root: URL
    private var prepared = false
    private var observation: AnyCancellable?

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMarker-TaskUI-\(UUID())")
        self.root = root
        store = HighlightTaskStore(fileURL: root.appendingPathComponent("highlight-tasks.json"))
        files = HighlightTaskFileStore(baseDirectory: root, temporaryDirectory: root.appendingPathComponent("tmp"))
        manager = HighlightTaskManager(store: store, fileStore: files, runner: TaskUIRunner(), validateSource: { _ in })
        observation = manager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func prepare() async {
        guard !prepared else { return }
        prepared = true
        do {
            let state = ProcessInfo.processInfo.environment["SHOTMARKER_UI_TEST_TASK_STATE"] ?? "completed"
            if state == "configuration" || state == "configuration-confirmed" {
                try await prepareConfiguration(confirmed: state == "configuration-confirmed")
                return
            }
            let video = HighlightTaskVideo(id: UUID(), sourceIdentity: .photoLibraryAsset("fixture"),
                recordedStartAt: Date(timeIntervalSince1970: 100), duration: 60, source: .photoLibraryAsset(localIdentifier: "fixture"))
            let session = TrainingSession(startedAt: video.recordedStartAt,
                endedAt: video.recordedStartAt.addingTimeInterval(60), events: [ShotMarkerEvent(markedAt: video.recordedStartAt.addingTimeInterval(10))])
            var task = try HighlightTaskPlanner.makeTask(id: UUID(), session: session, videos: [video], settings: .default)
            try await store.create(task)
            let first = try HighlightTaskPlanner.execution(for: task)
            _ = try await store.installExecution(taskID: task.id, expectedRevision: 1, execution: first)
            let id = UUID()
            let output = HighlightTaskOutput(id: id, relativePath: "HighlightTasks/\(task.id)/Outputs/\(id)/highlight.mov",
                configurationRevision: 1, generatedAt: Date())
            task = try await store.finishExecution(taskID: task.id, executionID: first.id, revision: 1, status: .succeeded, output: output)!
            if state == "modified" {
                var settings = task.clipSettings
                settings.markerLabelStyle.textOpacity = 0.5
                _ = try await store.updateConfiguration(id: task.id, expectedRevision: 1, videos: task.videos, settings: settings, items: task.reviewItems)
            } else if state == "queued" || state == "running" {
                let execution = try HighlightTaskPlanner.execution(for: task)
                _ = try await store.installExecution(taskID: task.id, expectedRevision: 1, execution: execution)
                if state == "running" {
                    _ = try await store.updateProgress(taskID: task.id, executionID: execution.id, revision: 1,
                        progress: HighlightJobProgress(completedMarkerCount: 0, totalMarkerCount: 1))
                }
            }
            await manager.refresh()
        } catch { assertionFailure("Task UI fixture failed to initialize") }
    }

    private func prepareConfiguration(confirmed: Bool) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("configuration.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        writer.add(input)
        guard writer.startWriting() else { throw HighlightTaskError.sourceUnavailable }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
              let buffer else { throw HighlightTaskError.sourceUnavailable }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 128, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for second in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(second), timescale: 1)) else {
                throw HighlightTaskError.sourceUnavailable
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 60, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw HighlightTaskError.sourceUnavailable }
        let start = Date(timeIntervalSince1970: 100)
        let training = TrainingSession(startedAt: start, endedAt: start.addingTimeInterval(60),
            events: [ShotMarkerEvent(markedAt: start.addingTimeInterval(confirmed ? 10 : 30))])
        let source = SelectedTrainingVideo(id: url.absoluteString, recordedStartAt: start, duration: 60)
        let task = try await manager.createTask(session: training, selectedVideos: [source], settings: .default)
        if confirmed {
            var items = task.reviewItems
            items[0].confirmationState = .confirmed
            items[0].framing = ClipFraming(scale: 2.2, centerX: 0.5, centerY: 0.5)
            _ = try await store.updateConfiguration(id: task.id, expectedRevision: 1,
                videos: task.videos, settings: task.clipSettings, items: items)
            await manager.refresh()
        }
    }
}

import Combine
private struct TaskUIRunner: HighlightRenderRunning {
    func run(execution: HighlightRenderExecution, outputURL: URL,
        onProgress: @escaping @MainActor (HighlightJobProgress) -> Void) async throws -> URL {
        throw CancellationError()
    }
}
#endif

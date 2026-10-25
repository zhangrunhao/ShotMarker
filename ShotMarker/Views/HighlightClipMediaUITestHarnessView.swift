#if DEBUG
    import AVFoundation
    import Combine
    import SwiftUI

    /// Real task persistence, navigation, playback and frame extraction for UI regression tests.
    struct HighlightClipMediaUITestHarnessView: View {
        @State private var session: HighlightReviewSession?
        @State private var preparationError: String?

        var body: some View {
            Group {
                if let session {
                    HighlightClipMediaUITestContent(session: session)
                } else if let preparationError {
                    Text(preparationError)
                        .accessibilityIdentifier("ClipMediaUIFixturePreparationError")
                } else {
                    ProgressView("正在准备测试视频…")
                }
            }
            .task {
                guard session == nil else { return }
                do {
                    session = try await makeSession()
                } catch {
                    preparationError = error.localizedDescription
                    print("Clip media UI fixture preparation failed: \(error.localizedDescription)")
                }
            }
        }

        @MainActor
        private func makeSession() async throws -> HighlightReviewSession {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ShotMarker-ClipMediaUI-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let first = root.appendingPathComponent("landscape.mov")
            let second = root.appendingPathComponent("portrait.mov")
            try await makeVideo(at: first, width: 160, height: 90, duration: 720,
                rotated: ProcessInfo.processInfo.environment["SHOTMARKER_UI_TEST_ROTATED_CLIP_SOURCE"] == "1")
            try await makeVideo(at: second, width: 90, height: 160, duration: 40)
            let files = HighlightTaskFileStore(baseDirectory: root, temporaryDirectory: root.appendingPathComponent("tmp"))
            let media = HighlightTaskMedia(fileStore: files)
            let manager = HighlightTaskManager(
                store: HighlightTaskStore(fileURL: root.appendingPathComponent("tasks.json")),
                fileStore: files,
                runner: HighlightRenderRunner(assetForVideo: { video, _ in try await media.asset(for: video) }, logger: AppLogger.shared),
                validateSource: { video in _ = try await media.asset(for: video).load(.duration) },
            )
            let start = Date(timeIntervalSince1970: 100_000)
            let training = TrainingSession(startedAt: start, endedAt: start.addingTimeInterval(760),
                events: [10.0, 12, 14, 700.1, 750].map { ShotMarkerEvent(markedAt: start.addingTimeInterval($0)) })
            let videos = [
                SelectedTrainingVideo(id: first.absoluteString, recordedStartAt: start, duration: 720),
                SelectedTrainingVideo(id: second.absoluteString, recordedStartAt: start.addingTimeInterval(720), duration: 40),
            ]
            let task = try await manager.createTask(session: training, selectedVideos: videos, settings: .default)
            return try HighlightReviewSession(task: task, manager: manager)
        }

        private func makeVideo(at url: URL, width: Int, height: Int, duration: Int, rotated: Bool = false) async throws {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            if rotated {
                input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
            }
            writer.add(input)
            guard writer.startWriting() else { throw HighlightClipReviewMediaError.assetLoadFailed }
            writer.startSession(atSourceTime: .zero)
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
                  let buffer
            else { throw HighlightClipReviewMediaError.assetLoadFailed }
            CVPixelBufferLockBaseAddress(buffer, [])
            let pixels = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * rowBytes + x * 4
                    // Marker positions describe upright coordinates for both encoded orientations.
                    let nx = rotated ? 1 - Double(y) / Double(height) : Double(x) / Double(width)
                    let ny = rotated ? Double(x) / Double(width) : Double(y) / Double(height)
                    let color: (UInt8, UInt8, UInt8) = nx < 0.2 ? (220, 30, 30)
                        : nx > 0.8 ? (30, 30, 220)
                        : (nx > 0.44 && nx < 0.56 && ny > 0.44 && ny < 0.56 ? (230, 230, 20) : (30, 180, 30))
                    pixels[offset] = color.2
                    pixels[offset + 1] = color.1
                    pixels[offset + 2] = color.0
                    pixels[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            for second in 0..<duration {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(second), timescale: 1)) else {
                    throw HighlightClipReviewMediaError.assetLoadFailed
                }
            }
            writer.endSession(atSourceTime: CMTime(value: Int64(duration), timescale: 1))
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw HighlightClipReviewMediaError.assetLoadFailed }
        }
    }

    private struct HighlightClipMediaUITestContent: View {
        @ObservedObject var session: HighlightReviewSession
        @StateObject private var playbackGate = ReopenedClipPlaybackGate()
        private let delaysReopenedPlayback = ProcessInfo.processInfo.environment["SHOTMARKER_UI_TEST_DELAY_REOPENED_CLIP"] == "1"

        var body: some View {
            NavigationStack {
                if delaysReopenedPlayback {
                    HighlightClipReviewView(viewModel: session.viewModel,
                        makePlaybackController: makeDelayedPlaybackController,
                        generationButtonTitle: "生成视频")
                } else {
                    HighlightTaskReviewView(session: session, onExit: {})
                }
            }
                .overlay(alignment: .topLeading) {
                    if let itemID = session.viewModel.editingItemID {
                        let frames = session.viewModel.filmstripFramesByItemID[itemID] ?? []
                        Text("\(frames.compactMap { $0 }.count)")
                            .font(.caption2)
                            .accessibilityIdentifier("ClipMediaLoadedFrameCount")
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if playbackGate.isWaiting {
                        Button("继续载入") { playbackGate.release() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("ClipMediaReleasePlaybackLoad")
                    } else if playbackGate.hasFinishedDelayedLoad {
                        Text("旧载入已返回")
                            .font(.caption2)
                            .accessibilityIdentifier("ClipMediaDelayedLoadFinished")
                            .allowsHitTesting(false)
                    }
                }
        }

        private func makeDelayedPlaybackController() -> HighlightClipPlaybackController {
            let isFirstItem = session.viewModel.editingItemID == session.viewModel.items.first?.id
            let provider = session.viewModel.mediaProvider
            return HighlightClipPlaybackController { video in
                let asset = try await provider.asset(for: video)
                let delayed = isFirstItem ? await playbackGate.waitForSecondOpening() : false
                defer {
                    if delayed { playbackGate.finishDelayedLoad() }
                }
                // Deliver the old asset even after cancellation to exercise load-generation rejection.
                return asset
            }
        }
    }

    @MainActor
    private final class ReopenedClipPlaybackGate: ObservableObject {
        @Published private(set) var isWaiting = false
        @Published private(set) var hasFinishedDelayedLoad = false
        private var firstItemLoadCount = 0
        private var continuation: CheckedContinuation<Void, Never>?

        func waitForSecondOpening() async -> Bool {
            firstItemLoadCount += 1
            guard firstItemLoadCount == 2 else { return false }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                isWaiting = true
            }
            return true
        }

        func release() {
            isWaiting = false
            continuation?.resume()
            continuation = nil
        }

        func finishDelayedLoad() {
            hasFinishedDelayedLoad = true
        }
    }
#endif

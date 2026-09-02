import AVFoundation
import Combine
import Foundation

@MainActor
protocol HighlightClipPlaybackEngine: AnyObject {
    var player: AVPlayer { get }
    func replaceCurrentItem(with asset: AVAsset)
    func clearCurrentItem()
    func play()
    func pause()
    func seek(to seconds: TimeInterval) async
    func addPeriodicTimeObserver(_ handler: @escaping (TimeInterval) -> Void) -> Any
    func addBoundaryTimeObserver(
        at seconds: TimeInterval,
        _ handler: @escaping () -> Void,
    ) -> Any
    func removeTimeObserver(_ token: Any)
}

@MainActor
final class AVPlayerHighlightClipPlaybackEngine: HighlightClipPlaybackEngine {
    let player = AVPlayer()

    func replaceCurrentItem(with asset: AVAsset) {
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
    }

    func clearCurrentItem() {
        player.replaceCurrentItem(with: nil)
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: TimeInterval) async {
        let time = CMTime(
            seconds: max(seconds, 0),
            preferredTimescale: HighlightClipPlaybackController.timescale,
        )
        await withCheckedContinuation { continuation in
            player.seek(
                to: time,
                toleranceBefore: .zero,
                toleranceAfter: .zero,
            ) { _ in
                continuation.resume()
            }
        }
    }

    func addPeriodicTimeObserver(
        _ handler: @escaping (TimeInterval) -> Void,
    ) -> Any {
        player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main,
        ) { time in
            handler(time.seconds)
        }
    }

    func addBoundaryTimeObserver(
        at seconds: TimeInterval,
        _ handler: @escaping () -> Void,
    ) -> Any {
        let time = CMTime(
            seconds: max(seconds, 0),
            preferredTimescale: HighlightClipPlaybackController.timescale,
        )
        return player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: time)],
            queue: .main,
            using: handler,
        )
    }

    func removeTimeObserver(_ token: Any) {
        player.removeTimeObserver(token)
    }
}

@MainActor
final class HighlightClipPlaybackController: ObservableObject {
    typealias LoadAsset = (SelectedTrainingVideo) async throws -> AVAsset

    static let timescale: CMTimeScale = 600
    private static let endPreviewOffset = 1.0 / TimeInterval(timescale)

    @Published private(set) var player: AVPlayer
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: HighlightClipReviewMediaError?
    @Published private(set) var errorMessage: String?

    private let engine: HighlightClipPlaybackEngine
    private let loadAsset: LoadAsset
    private var activeRange: HighlightClipRange?
    private var periodicObserverToken: Any?
    private var boundaryObserverToken: Any?
    private var hasLoadedItem = false
    private var loadGeneration = 0

    init(
        engine: HighlightClipPlaybackEngine,
        loadAsset: @escaping LoadAsset,
    ) {
        self.engine = engine
        self.loadAsset = loadAsset
        player = engine.player
    }

    convenience init(loadAsset: @escaping LoadAsset) {
        self.init(
            engine: AVPlayerHighlightClipPlaybackEngine(),
            loadAsset: loadAsset,
        )
    }

    isolated deinit {
        removeObservers()
        if hasLoadedItem {
            engine.pause()
            engine.clearCurrentItem()
        }
    }

    func load(video: SelectedTrainingVideo, range: HighlightClipRange) async {
        guard Self.isValid(range: range, videoDuration: video.duration) else {
            publishLoadFailure(.invalidRequest)
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        releaseLoadedItem()
        activeRange = nil
        currentTime = 0
        isLoading = true
        isPlaying = false
        loadError = nil
        errorMessage = nil

        let asset: AVAsset
        do {
            asset = try await loadAsset(video)
        } catch let error as HighlightClipReviewMediaError {
            guard generation == loadGeneration else {
                return
            }
            publishLoadFailure(error)
            return
        } catch {
            guard generation == loadGeneration else {
                return
            }
            publishLoadFailure(.assetLoadFailed)
            return
        }

        guard generation == loadGeneration else {
            return
        }

        engine.replaceCurrentItem(with: asset)
        hasLoadedItem = true
        activeRange = range
        installObservers(for: range)
        engine.pause()
        await engine.seek(to: range.start)

        guard generation == loadGeneration, hasLoadedItem else {
            return
        }
        currentTime = range.start
        isLoading = false
    }

    func play() {
        guard hasLoadedItem,
              !isLoading,
              loadError == nil,
              let activeRange
        else {
            return
        }

        isPlaying = true
        guard currentTime >= activeRange.start,
              currentTime < activeRange.end
        else {
            currentTime = activeRange.start
            let generation = loadGeneration
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await engine.seek(to: activeRange.start)
                guard generation == loadGeneration,
                      hasLoadedItem,
                      isPlaying
                else {
                    return
                }
                engine.play()
            }
            return
        }

        engine.play()
    }

    func pause() {
        guard hasLoadedItem else {
            isPlaying = false
            return
        }

        engine.pause()
        isPlaying = false
    }

    func preview(at time: TimeInterval) async {
        guard hasLoadedItem, time.isFinite, time >= 0 else {
            return
        }

        pause()
        let generation = loadGeneration
        await engine.seek(to: time)
        guard generation == loadGeneration, hasLoadedItem else {
            return
        }
        currentTime = time
    }

    func previewStart(of range: HighlightClipRange) async {
        guard Self.isValidPreviewRange(range) else {
            return
        }

        await preview(at: range.start)
    }

    func previewEnd(of range: HighlightClipRange) async {
        guard Self.isValidPreviewRange(range) else {
            return
        }

        await preview(at: max(range.start, range.end - Self.endPreviewOffset))
    }

    func updateRange(_ range: HighlightClipRange) {
        guard hasLoadedItem, Self.isValidPreviewRange(range) else {
            return
        }

        let previousEnd = activeRange?.end
        activeRange = range
        if previousEnd != range.end {
            replaceBoundaryObserver(at: range.end)
        }
    }

    func reset() {
        loadGeneration &+= 1
        releaseLoadedItem()
        activeRange = nil
        currentTime = 0
        isPlaying = false
        isLoading = false
        loadError = nil
        errorMessage = nil
    }

    private func installObservers(for range: HighlightClipRange) {
        periodicObserverToken = engine.addPeriodicTimeObserver { [weak self] time in
            guard let self, time.isFinite else {
                return
            }
            currentTime = time
        }
        replaceBoundaryObserver(at: range.end)
    }

    private func replaceBoundaryObserver(at end: TimeInterval) {
        if let boundaryObserverToken {
            engine.removeTimeObserver(boundaryObserverToken)
            self.boundaryObserverToken = nil
        }

        boundaryObserverToken = engine.addBoundaryTimeObserver(at: end) { [weak self] in
            self?.finishAtBoundary()
        }
    }

    private func finishAtBoundary() {
        guard hasLoadedItem, let activeRange else {
            return
        }

        engine.pause()
        isPlaying = false
        currentTime = activeRange.start
        let generation = loadGeneration
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await engine.seek(to: activeRange.start)
            guard generation == loadGeneration else {
                return
            }
        }
    }

    private func releaseLoadedItem() {
        removeObservers()
        guard hasLoadedItem else {
            return
        }

        engine.pause()
        engine.clearCurrentItem()
        hasLoadedItem = false
    }

    private func removeObservers() {
        if let periodicObserverToken {
            engine.removeTimeObserver(periodicObserverToken)
            self.periodicObserverToken = nil
        }
        if let boundaryObserverToken {
            engine.removeTimeObserver(boundaryObserverToken)
            self.boundaryObserverToken = nil
        }
    }

    private func publishLoadFailure(_ error: HighlightClipReviewMediaError) {
        isLoading = false
        isPlaying = false
        loadError = error
        errorMessage = error.errorDescription
    }

    private static func isValid(
        range: HighlightClipRange,
        videoDuration: TimeInterval,
    ) -> Bool {
        isValidPreviewRange(range)
            && videoDuration.isFinite
            && videoDuration > 0
            && range.end <= videoDuration
    }

    private static func isValidPreviewRange(_ range: HighlightClipRange) -> Bool {
        range.start.isFinite
            && range.duration.isFinite
            && range.start >= 0
            && range.duration > 0
            && range.end.isFinite
    }
}

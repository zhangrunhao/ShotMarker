import AVFoundation
import Combine
import Foundation

@MainActor
final class HighlightClipPlaybackController: ObservableObject {
    typealias LoadUprightSize = (AVAsset) async throws -> CGSize

    @Published private(set) var uprightVideoSize: CGSize?

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
    private let loadUprightSize: LoadUprightSize
    private var activeRange: HighlightClipRange?
    private var periodicObserverToken: Any?
    private var boundaryObserverToken: Any?
    private var hasLoadedItem = false
    private var loadGeneration = 0
    private var seekGeneration = 0
    private var boundaryObserverGeneration = 0
    private var pendingSeek: SeekRequest?

    private struct SeekRequest {
        let loadGeneration: Int
        let seekGeneration: Int
        let target: TimeInterval
    }

    var isSourceSizeUnavailable: Bool {
        hasLoadedItem && !isLoading && loadError == nil && uprightVideoSize == nil
    }

    init(
        engine: HighlightClipPlaybackEngine,
        loadAsset: @escaping LoadAsset,
        loadUprightSize: LoadUprightSize? = nil,
    ) {
        self.engine = engine
        self.loadAsset = loadAsset
        self.loadUprightSize = loadUprightSize ?? Self.loadSourceSize
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
        // Every request supersedes prior media work, including an invalid request.
        reset()
        let generation = loadGeneration
        guard Self.isValid(range: range, videoDuration: video.duration) else {
            publishLoadFailure(.invalidRequest)
            return
        }
        isLoading = true

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

        let sourceSize = try? await loadUprightSize(asset)
        guard generation == loadGeneration else { return }
        if let sourceSize, sourceSize.width.isFinite, sourceSize.height.isFinite,
           sourceSize.width > 0, sourceSize.height > 0 {
            uprightVideoSize = sourceSize
        }

        engine.replaceCurrentItem(with: asset)
        hasLoadedItem = true
        activeRange = range
        installObservers(for: range)
        engine.pause()
        await seek(request: makeSeekRequest(to: range.start))

        guard generation == loadGeneration, hasLoadedItem else {
            return
        }
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
        let target = pendingSeek?.target ?? currentTime
        let isWithinRange = target >= activeRange.start && target < activeRange.end
        if pendingSeek != nil || !isWithinRange {
            let replayTime = isWithinRange ? target : activeRange.start
            currentTime = replayTime
            let request = makeSeekRequest(to: replayTime)
            Task { @MainActor [weak self] in
                guard let self, await seek(request: request), isCurrent(request), isPlaying else { return }
                engine.play()
            }
            return
        }

        // Supersede any previous post-seek play continuation without creating
        // an unfinished seek when the player is already at the desired position.
        seekGeneration &+= 1
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
        await seek(request: makeSeekRequest(to: time))
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
        seekGeneration &+= 1
        pendingSeek = nil
        releaseLoadedItem()
        activeRange = nil
        uprightVideoSize = nil
        currentTime = 0
        isPlaying = false
        isLoading = false
        loadError = nil
        errorMessage = nil
    }

    private func installObservers(for range: HighlightClipRange) {
        let generation = loadGeneration
        periodicObserverToken = engine.addPeriodicTimeObserver { [weak self] time in
            guard let self, generation == loadGeneration, hasLoadedItem, time.isFinite else {
                return
            }
            currentTime = time
        }
        replaceBoundaryObserver(at: range.end)
    }

    private func replaceBoundaryObserver(at end: TimeInterval) {
        boundaryObserverGeneration &+= 1
        let observerGeneration = boundaryObserverGeneration
        let generation = loadGeneration
        if let boundaryObserverToken {
            engine.removeTimeObserver(boundaryObserverToken)
            self.boundaryObserverToken = nil
        }

        boundaryObserverToken = engine.addBoundaryTimeObserver(at: end) { [weak self] in
            guard let self, generation == loadGeneration,
                  observerGeneration == boundaryObserverGeneration else { return }
            finishAtBoundary()
        }
    }

    private func finishAtBoundary() {
        guard hasLoadedItem, let activeRange else {
            return
        }

        engine.pause()
        isPlaying = false
        currentTime = activeRange.start
        let request = makeSeekRequest(to: activeRange.start)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await seek(request: request)
        }
    }

    private func makeSeekRequest(to target: TimeInterval) -> SeekRequest {
        seekGeneration &+= 1
        let request = SeekRequest(loadGeneration: loadGeneration, seekGeneration: seekGeneration, target: target)
        pendingSeek = request
        return request
    }

    private func isCurrent(_ request: SeekRequest) -> Bool {
        hasLoadedItem && request.loadGeneration == loadGeneration
            && request.seekGeneration == seekGeneration
    }

    @discardableResult
    private func seek(request: SeekRequest) async -> Bool {
        // Check before seeking too: a queued Task may outlive its source item.
        guard isCurrent(request) else { return false }
        await engine.seek(to: request.target)
        guard isCurrent(request) else { return false }
        pendingSeek = nil
        currentTime = request.target
        return true
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
        boundaryObserverGeneration &+= 1
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
        uprightVideoSize = nil
        isLoading = false
        isPlaying = false
        loadError = error
        errorMessage = error.errorDescription
    }

    static func loadSourceSize(_ asset: AVAsset) async throws -> CGSize {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw HighlightClipReviewMediaError.assetLoadFailed
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        return ClipFramingGeometry.uprightBounds(naturalSize: naturalSize, preferredTransform: transform).size
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

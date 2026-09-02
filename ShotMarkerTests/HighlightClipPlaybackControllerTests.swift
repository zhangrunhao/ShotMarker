@testable import ShotMarker
import AVFoundation
import XCTest

final class HighlightClipPlaybackControllerTests: XCTestCase {
    @MainActor
    func testLoadPausesAtRangeStartWithoutAutoplay() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let controller = makeController(engine: engine)

        await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))

        XCTAssertTrue(controller.player === engine.player)
        XCTAssertEqual(engine.replacedAssetCount, 1)
        XCTAssertEqual(engine.seekedTimes, [4])
        XCTAssertEqual(engine.pauseCallCount, 1)
        XCTAssertEqual(engine.playCallCount, 0)
        XCTAssertEqual(controller.currentTime, 4)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isLoading)
        XCTAssertNil(controller.loadError)
    }

    @MainActor
    func testPlayStopsAtEndAndReturnsToStart() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let controller = makeController(engine: engine)
        await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))

        controller.play()
        engine.fireBoundaryObserver()
        await Task.yield()

        XCTAssertEqual(engine.playCallCount, 1)
        XCTAssertEqual(engine.pauseCallCount, 2)
        XCTAssertEqual(engine.seekedTimes.last, 4)
        XCTAssertEqual(controller.currentTime, 4)
        XCTAssertFalse(controller.isPlaying)
    }

    @MainActor
    func testRangeAndCursorPreviewPauseAtSpecifiedFrames() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let controller = makeController(engine: engine)
        await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))

        await controller.previewStart(of: .init(start: 5, duration: 2))
        await controller.previewEnd(of: .init(start: 5, duration: 2))
        await controller.preview(at: 5.5)

        XCTAssertEqual(engine.seekedTimes[1], 5)
        XCTAssertEqual(engine.seekedTimes[2], 7 - 1.0 / 600.0, accuracy: 0.000_001)
        XCTAssertEqual(engine.seekedTimes[3], 5.5)
        XCTAssertEqual(controller.currentTime, 5.5)
        XCTAssertFalse(controller.isPlaying)
    }

    @MainActor
    func testSwitchAndResetRemoveObserversAndReleasePlayerItem() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let controller = makeController(engine: engine)
        await controller.load(
            video: makeVideo(id: "first"),
            range: .init(start: 0, duration: 2),
        )
        await controller.load(
            video: makeVideo(id: "second"),
            range: .init(start: 1, duration: 2),
        )
        controller.reset()

        XCTAssertEqual(engine.removedObserverCount, 4)
        XCTAssertEqual(engine.clearCallCount, 2)
        XCTAssertNil(engine.periodicHandler)
        XCTAssertNil(engine.boundaryHandler)
    }

    @MainActor
    func testPeriodicCallbackUpdatesCurrentTime() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let controller = makeController(engine: engine)
        await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))

        engine.firePeriodicObserver(at: 5.25)

        XCTAssertEqual(controller.currentTime, 5.25)
    }

    @MainActor
    func testPlaySeeksToStartWhenCursorIsOutsideSelection() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let controller = makeController(engine: engine)
        await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))
        engine.firePeriodicObserver(at: 8)

        controller.play()
        await Task.yield()

        XCTAssertEqual(engine.seekedTimes.last, 4)
        XCTAssertEqual(engine.playCallCount, 1)
        XCTAssertEqual(controller.currentTime, 4)
        XCTAssertTrue(controller.isPlaying)
    }

    @MainActor
    func testUpdatingRangeEndReplacesOnlyBoundaryObserver() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let controller = makeController(engine: engine)
        await controller.load(video: makeVideo(), range: .init(start: 4, duration: 3))

        controller.updateRange(.init(start: 5, duration: 4))

        XCTAssertEqual(engine.boundaryTimes, [7, 9])
        XCTAssertEqual(engine.removedObserverCount, 1)
        XCTAssertNotNil(engine.periodicHandler)
        XCTAssertNotNil(engine.boundaryHandler)
    }

    @MainActor
    func testAssetLoadFailureExposesRetryableTypedErrorWithoutReplacingItem() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let range = HighlightClipRange(start: 4, duration: 3)
        let controller = makeController(engine: engine) { _ in
            throw PlaybackTestError.loadFailed
        }

        await controller.load(video: makeVideo(), range: range)

        XCTAssertEqual(controller.loadError, .assetLoadFailed)
        XCTAssertEqual(controller.errorMessage, HighlightClipReviewMediaError.assetLoadFailed.errorDescription)
        XCTAssertFalse(controller.isLoading)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(engine.replacedAssetCount, 0)
        XCTAssertTrue(engine.seekedTimes.isEmpty)
        XCTAssertEqual(range, .init(start: 4, duration: 3))
    }

    @MainActor
    func testSourceUnavailableRemainsDistinguishableWithoutReplacingItem() async {
        let engine = SpyHighlightClipPlaybackEngine()
        let range = HighlightClipRange(start: 4, duration: 3)
        let controller = makeController(engine: engine) { _ in
            throw HighlightClipReviewMediaError.sourceUnavailable
        }

        await controller.load(video: makeVideo(), range: range)

        XCTAssertEqual(controller.loadError, .sourceUnavailable)
        XCTAssertEqual(controller.errorMessage, HighlightClipReviewMediaError.sourceUnavailable.errorDescription)
        XCTAssertEqual(engine.replacedAssetCount, 0)
        XCTAssertTrue(engine.seekedTimes.isEmpty)
        XCTAssertEqual(range, .init(start: 4, duration: 3))
    }

    @MainActor
    func testDeinitializationRemovesObserversAndReleasesPlayerItem() async {
        let engine = SpyHighlightClipPlaybackEngine()
        var controller: HighlightClipPlaybackController? = makeController(engine: engine)
        await controller?.load(video: makeVideo(), range: .init(start: 4, duration: 3))
        weak var weakController = controller

        controller = nil

        XCTAssertNil(weakController)
        XCTAssertEqual(engine.removedObserverCount, 2)
        XCTAssertEqual(engine.clearCallCount, 1)
    }

    @MainActor
    private func makeController(
        engine: SpyHighlightClipPlaybackEngine,
        loadAsset: @escaping (SelectedTrainingVideo) async throws -> AVAsset = { _ in
            AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov"))
        },
    ) -> HighlightClipPlaybackController {
        HighlightClipPlaybackController(engine: engine, loadAsset: loadAsset)
    }

    private func makeVideo(id: String = "video") -> SelectedTrainingVideo {
        SelectedTrainingVideo(
            id: id,
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
    }
}

private enum PlaybackTestError: Error {
    case loadFailed
}

@MainActor
private final class SpyHighlightClipPlaybackEngine: HighlightClipPlaybackEngine {
    let player = AVPlayer()
    private let periodicToken = UUID()
    private let boundaryToken = UUID()
    private(set) var replacedAssetCount = 0
    private(set) var clearCallCount = 0
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var seekedTimes: [TimeInterval] = []
    private(set) var removedObserverCount = 0
    private(set) var boundaryTimes: [TimeInterval] = []
    private(set) var periodicHandler: ((TimeInterval) -> Void)?
    private(set) var boundaryHandler: (() -> Void)?

    func replaceCurrentItem(with _: AVAsset) {
        replacedAssetCount += 1
    }

    func clearCurrentItem() {
        clearCallCount += 1
    }

    func play() {
        playCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func seek(to seconds: TimeInterval) async {
        seekedTimes.append(seconds)
    }

    func addPeriodicTimeObserver(
        _ handler: @escaping (TimeInterval) -> Void,
    ) -> Any {
        periodicHandler = handler
        return periodicToken
    }

    func addBoundaryTimeObserver(
        at seconds: TimeInterval,
        _ handler: @escaping () -> Void,
    ) -> Any {
        boundaryTimes.append(seconds)
        boundaryHandler = handler
        return boundaryToken
    }

    func removeTimeObserver(_ token: Any) {
        removedObserverCount += 1
        if let token = token as? UUID {
            if token == periodicToken {
                periodicHandler = nil
            } else if token == boundaryToken {
                boundaryHandler = nil
            }
        }
    }

    func firePeriodicObserver(at time: TimeInterval) {
        periodicHandler?(time)
    }

    func fireBoundaryObserver() {
        boundaryHandler?()
    }
}

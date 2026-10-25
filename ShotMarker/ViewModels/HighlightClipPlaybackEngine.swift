import AVFoundation
import Foundation

@MainActor
protocol HighlightClipPlaybackEngine: AnyObject {
    var player: AVPlayer { get }
    func replaceCurrentItem(with asset: AVAsset)
    func clearCurrentItem()
    func play()
    func pause()
    func seek(to seconds: TimeInterval) async
    func addPeriodicTimeObserver(_ handler: @escaping @MainActor @Sendable (TimeInterval) -> Void) -> Any
    func addBoundaryTimeObserver(
        at seconds: TimeInterval,
        _ handler: @escaping @MainActor @Sendable () -> Void,
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
        _ handler: @escaping @MainActor @Sendable (TimeInterval) -> Void,
    ) -> Any {
        player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main,
        ) { time in
            MainActor.assumeIsolated { handler(time.seconds) }
        }
    }

    func addBoundaryTimeObserver(
        at seconds: TimeInterval,
        _ handler: @escaping @MainActor @Sendable () -> Void,
    ) -> Any {
        let time = CMTime(
            seconds: max(seconds, 0),
            preferredTimescale: HighlightClipPlaybackController.timescale,
        )
        return player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: time)],
            queue: .main,
            using: { MainActor.assumeIsolated { handler() } },
        )
    }

    func removeTimeObserver(_ token: Any) {
        player.removeTimeObserver(token)
    }
}

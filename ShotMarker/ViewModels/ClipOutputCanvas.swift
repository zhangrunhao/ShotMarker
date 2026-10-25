import AVFoundation
import Combine

/// Metadata for the first retained source determines the output coordinate space.
@MainActor
final class ClipOutputCanvas: ObservableObject {
    typealias LoadSize = (SelectedTrainingVideo) async throws -> CGSize
    @Published private(set) var size: CGSize?
    @Published private(set) var failed = false
    private var generation = 0
    private let loadSize: LoadSize

    init(loadSize: @escaping LoadSize) { self.loadSize = loadSize }

    convenience init(provider: HighlightClipReviewMediaProvider) {
        self.init { video in
            let asset = try await provider.asset(for: video)
            return try await HighlightClipPlaybackController.loadSourceSize(asset)
        }
    }

    func load(video: SelectedTrainingVideo) async {
        generation += 1
        let expected = generation
        size = nil
        failed = false
        do {
            let loaded = try await loadSize(video)
            guard expected == generation, !Task.isCancelled else { return }
            guard loaded.width.isFinite, loaded.height.isFinite, loaded.width > 0, loaded.height > 0 else {
                throw HighlightClipReviewMediaError.assetLoadFailed
            }
            size = loaded
        } catch {
            guard expected == generation, !Task.isCancelled else { return }
            failed = true
        }
    }

    func reset() {
        generation += 1
        size = nil
        failed = false
    }
}

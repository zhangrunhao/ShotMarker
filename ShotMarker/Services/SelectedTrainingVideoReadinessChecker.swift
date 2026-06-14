import Foundation

struct SelectedTrainingVideoReadinessChecker {
    typealias VerifyPhotoLibraryAssetIsLocal = (String) async throws -> Void

    private let verifyPhotoLibraryAssetIsLocal: VerifyPhotoLibraryAssetIsLocal

    init(verifyPhotoLibraryAssetIsLocal: @escaping VerifyPhotoLibraryAssetIsLocal) {
        self.verifyPhotoLibraryAssetIsLocal = verifyPhotoLibraryAssetIsLocal
    }

    func ensureReady(_ video: SelectedTrainingVideo) async throws {
        guard Self.temporaryVideoURL(from: video.id) == nil else {
            return
        }

        try await verifyPhotoLibraryAssetIsLocal(video.id)
    }

    static func temporaryVideoURL(from videoID: String) -> URL? {
        guard let url = URL(string: videoID), url.isFileURL else {
            return nil
        }

        return url
    }
}

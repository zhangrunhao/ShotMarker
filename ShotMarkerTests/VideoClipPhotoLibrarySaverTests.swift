@testable import ShotMarker
import Photos
import XCTest

final class VideoClipPhotoLibrarySaverTests: XCTestCase {
    func testSaveVideoRequestsAddOnlyAccessAndSavesWhenAuthorized() async throws {
        let videoURL = URL(fileURLWithPath: "/tmp/test.mov")
        var savedURLs: [URL] = []
        let saver = VideoClipPhotoLibrarySaver(
            requestAuthorization: { .authorized },
            saveVideoToLibrary: { savedURLs.append($0) },
        )

        try await saver.saveVideo(at: videoURL)

        XCTAssertEqual(savedURLs, [videoURL])
    }

    func testSaveVideoThrowsWhenAccessIsDenied() async {
        let saver = VideoClipPhotoLibrarySaver(
            requestAuthorization: { .denied },
            saveVideoToLibrary: { _ in XCTFail("Should not save without photo library access") },
        )

        do {
            try await saver.saveVideo(at: URL(fileURLWithPath: "/tmp/test.mov"))
            XCTFail("Expected photo library access error")
        } catch VideoClipPhotoLibraryError.accessDenied {
            // Expected path.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

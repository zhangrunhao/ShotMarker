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

    func testPhotoLibraryVideoAccessTreatsNetworkErrorAsPickerFallbackCandidate() {
        let error = NSError(domain: PHPhotosErrorDomain, code: 3169)

        XCTAssertTrue(PhotoLibraryVideoAccess.shouldFallbackToPickerFile(for: error))
    }

    func testPhotoLibraryVideoAccessMapsNetworkErrorToActionableMessage() {
        let error = NSError(domain: PHPhotosErrorDomain, code: 3169)
        let userFacingError = PhotoLibraryVideoAccess.userFacingError(for: error)

        XCTAssertEqual(
            (userFacingError as? LocalizedError)?.errorDescription,
            "无法从 iCloud 读取所选视频。请确认网络可用，或先在照片 App 打开这个视频让它下载完成后再试。",
        )
    }
}

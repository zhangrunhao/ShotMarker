@testable import ShotMarker
import XCTest

final class SelectedTrainingVideoReadinessCheckerTests: XCTestCase {
    func testEnsureReadySkipsLocalFileVideos() async throws {
        var verifiedAssetIdentifiers: [String] = []
        let checker = SelectedTrainingVideoReadinessChecker { assetIdentifier in
            verifiedAssetIdentifiers.append(assetIdentifier)
        }
        let video = SelectedTrainingVideo(
            id: URL(fileURLWithPath: "/tmp/video.mov").absoluteString,
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        try await checker.ensureReady(video)

        XCTAssertEqual(verifiedAssetIdentifiers, [])
    }

    func testEnsureReadyVerifiesPhotoLibraryAssetVideos() async throws {
        var verifiedAssetIdentifiers: [String] = []
        let checker = SelectedTrainingVideoReadinessChecker { assetIdentifier in
            verifiedAssetIdentifiers.append(assetIdentifier)
        }
        let video = SelectedTrainingVideo(
            id: "photo-library-asset-id",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        try await checker.ensureReady(video)

        XCTAssertEqual(verifiedAssetIdentifiers, ["photo-library-asset-id"])
    }

    func testEnsureReadyPropagatesPhotoLibraryReadinessFailure() async {
        let checker = SelectedTrainingVideoReadinessChecker { _ in
            throw ReadinessError.notReady
        }
        let video = SelectedTrainingVideo(
            id: "photo-library-asset-id",
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )

        do {
            try await checker.ensureReady(video)
            XCTFail("Expected readiness failure")
        } catch {
            XCTAssertEqual(error as? ReadinessError, .notReady)
        }
    }

    private enum ReadinessError: Error, Equatable {
        case notReady
    }
}

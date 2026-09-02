#if os(iOS)
    @testable import ShotMarker
    import Photos
    import XCTest

    final class PhotoLibraryVideoAssetProviderTests: XCTestCase {
        func testThumbnailRequestPreservesFullFrameWithoutNetworkAccess() {
            let options = PhotoLibraryVideoAssetProvider.makeThumbnailRequestOptions()

            XCTAssertEqual(
                PhotoLibraryVideoAssetProvider.thumbnailTargetSize,
                CGSize(width: 320, height: 320),
            )
            XCTAssertEqual(PhotoLibraryVideoAssetProvider.thumbnailContentMode, .aspectFit)
            XCTAssertEqual(options.deliveryMode, .fastFormat)
            XCTAssertEqual(options.resizeMode, .fast)
            XCTAssertFalse(options.isNetworkAccessAllowed)
            XCTAssertTrue(options.isSynchronous)
        }
    }
#endif

#if os(iOS)
    @testable import ShotMarker
    import XCTest

    final class TrainingVideoTemporaryFileStoreTests: XCTestCase {
        func testTemporaryVideoURLReturnsOnlyFileURLs() {
            let store = TrainingVideoTemporaryFileStore()
            let fileURL = URL(fileURLWithPath: "/tmp/ShotMarker/video.mov")

            XCTAssertEqual(store.temporaryVideoURL(from: fileURL.absoluteString), fileURL)
            XCTAssertNil(store.temporaryVideoURL(from: "photo-library-asset-id"))
            XCTAssertNil(store.temporaryVideoURL(from: "https://example.com/video.mov"))
        }

        func testCleanupTemporaryVideosRemovesLocalFileVideos() throws {
            let store = TrainingVideoTemporaryFileStore()
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ShotMarkerTempStoreTests-\(UUID().uuidString)", isDirectory: true)
            let videoURL = directoryURL.appendingPathComponent("picked.mov")
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: videoURL)
            defer {
                try? FileManager.default.removeItem(at: directoryURL)
            }

            store.cleanupTemporaryVideos([
                SelectedTrainingVideo(
                    id: videoURL.absoluteString,
                    recordedStartAt: Date(timeIntervalSince1970: 100),
                    duration: 60,
                ),
                SelectedTrainingVideo(
                    id: "photo-library-asset-id",
                    recordedStartAt: Date(timeIntervalSince1970: 100),
                    duration: 60,
                ),
            ])

            XCTAssertFalse(FileManager.default.fileExists(atPath: videoURL.path))
        }
    }
#endif

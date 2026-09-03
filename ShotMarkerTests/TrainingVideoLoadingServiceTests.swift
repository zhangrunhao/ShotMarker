#if os(iOS)
    @testable import ShotMarker
    import PhotosUI
    import SwiftUI
    import XCTest

    final class TrainingVideoLoadingServiceTests: XCTestCase {
        func testLoadSelectionItemReturnsMissingRecordedStartReason() async throws {
            let service = makeService(
                loadPhotoLibraryVideo: { assetIdentifier in
                    throw SelectedTrainingVideoLoadFailure(
                        id: assetIdentifier,
                        thumbnailData: Data([1, 2, 3]),
                        error: HighlightVideoSelectionError.missingRecordedStartAt,
                    )
                },
                loadPickedVideo: { _ in
                    throw HighlightVideoSelectionError.videoLoadFailed
                },
            )

            let item = await service.loadSelectionItem(
                from: "photo",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(item.id, "asset-id")
            XCTAssertEqual(item.unavailableReason, .missingRecordedStartAt)
            XCTAssertEqual(item.thumbnailData, Data([1, 2, 3]))
        }

        func testLoadSelectionItemReturnsInvalidDurationReason() async throws {
            let service = makeService(
                loadPhotoLibraryVideo: { assetIdentifier in
                    throw SelectedTrainingVideoLoadFailure(
                        id: assetIdentifier,
                        thumbnailData: nil,
                        error: HighlightVideoSelectionError.invalidDuration,
                    )
                },
                loadPickedVideo: { _ in
                    throw HighlightVideoSelectionError.videoLoadFailed
                },
            )

            let item = await service.loadSelectionItem(
                from: "photo",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(item.id, "asset-id")
            XCTAssertEqual(item.unavailableReason, .invalidDuration)
        }

        func testLoadSelectionItemFallsBackToPickedVideoWhenPhotoLibraryLoadFails() async throws {
            var pickedVideoLoadCount = 0
            let pickedVideo = SelectedTrainingVideo(
                id: URL(fileURLWithPath: "/tmp/picked.mov").absoluteString,
                recordedStartAt: Date(timeIntervalSince1970: 100),
                duration: 60,
            )
            let service = makeService(
                loadPhotoLibraryVideo: { _ in
                    throw HighlightVideoSelectionError.photoLibraryAccessDenied
                },
                loadPickedVideo: { _ in
                    pickedVideoLoadCount += 1
                    return LoadedTrainingVideo(video: pickedVideo, thumbnailData: Data([9]))
                },
            )

            let item = await service.loadSelectionItem(
                from: "photo",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(pickedVideoLoadCount, 1)
            XCTAssertTrue(item.isAvailable)
            XCTAssertEqual(item.video, pickedVideo)
            XCTAssertEqual(item.thumbnailData, Data([9]))
        }

        func testLoadSelectionItemReturnsNoMarkerCoverageAndRemovesTemporaryVideo() async throws {
            var removedVideoIDs: [String] = []
            let pickedVideo = SelectedTrainingVideo(
                id: URL(fileURLWithPath: "/tmp/out-of-range.mov").absoluteString,
                recordedStartAt: Date(timeIntervalSince1970: 300),
                duration: 60,
            )
            let service = makeService(
                assetIdentifier: { _ in nil },
                loadPhotoLibraryVideo: { _ in
                    throw HighlightVideoSelectionError.videoLoadFailed
                },
                loadPickedVideo: { _ in
                    LoadedTrainingVideo(video: pickedVideo, thumbnailData: Data([4]))
                },
                removeTemporaryVideoIfNeeded: { video in
                    removedVideoIDs.append(video.id)
                },
            )

            let item = await service.loadSelectionItem(
                from: "picked",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(item.id, pickedVideo.id)
            XCTAssertEqual(item.unavailableReason, .noMarkerCoverage)
            XCTAssertEqual(item.thumbnailData, Data([4]))
            XCTAssertEqual(removedVideoIDs, [pickedVideo.id])
        }

        func testLoadSelectionItemReturnsNotReadyWithVideoForPreparation() async throws {
            let video = SelectedTrainingVideo(
                id: "asset-id",
                recordedStartAt: Date(timeIntervalSince1970: 100),
                duration: 60,
            )
            let service = makeService(
                loadPhotoLibraryVideo: { _ in
                    LoadedTrainingVideo(video: video, thumbnailData: Data([5]))
                },
                loadPickedVideo: { _ in
                    throw HighlightVideoSelectionError.videoLoadFailed
                },
                ensureReady: { _ in
                    throw HighlightVideoSelectionError.videoNotReady
                },
            )

            let item = await service.loadSelectionItem(
                from: "photo",
                title: "视频 1",
                fallbackID: "selection-1",
                session: makeSession(),
            )

            XCTAssertEqual(item.id, video.id)
            XCTAssertEqual(item.video, video)
            XCTAssertEqual(item.unavailableReason, .notReady)
            XCTAssertEqual(item.thumbnailData, Data([5]))
        }

        func testPhotoLibraryVideoUsesAssetIdentityWithoutHashing() async throws {
            let metadata = TrainingVideoMetadata(
                recordedStartAt: Date(timeIntervalSince1970: 100),
                duration: 60,
            )
            let hasher = SpyContentHasher(result: .failure(TestError.unexpectedHash))

            let video = try await TrainingVideoLoadingService<PhotosPickerItem>.makeReviewIdentifiedVideo(
                runtimeID: "asset-1",
                photoLibraryIdentifier: "asset-1",
                temporaryFileURL: URL(fileURLWithPath: "/tmp/fallback-copy.mov"),
                metadata: metadata,
                contentHasher: hasher,
            )

            XCTAssertEqual(video.id, "asset-1")
            XCTAssertEqual(video.reviewSourceIdentity, .photoLibraryAsset("asset-1"))
            XCTAssertEqual(hasher.callCount, 0)
        }

        func testPickedFileUsesContentDigestAndKeepsRuntimeURLSeparate() async throws {
            let url = URL(fileURLWithPath: "/tmp/runtime-copy.mov")
            let hasher = SpyContentHasher(result: .success(String(repeating: "a", count: 64)))

            let video = try await TrainingVideoLoadingService<PhotosPickerItem>.makeReviewIdentifiedVideo(
                runtimeID: url.absoluteString,
                photoLibraryIdentifier: nil,
                temporaryFileURL: url,
                metadata: TrainingVideoMetadata(
                    recordedStartAt: Date(timeIntervalSince1970: 100),
                    duration: 60,
                ),
                contentHasher: hasher,
            )

            XCTAssertEqual(video.id, url.absoluteString)
            XCTAssertEqual(video.reviewSourceIdentity, .fileSHA256(String(repeating: "a", count: 64)))
            XCTAssertEqual(hasher.callCount, 1)
        }

        func testTemporaryRuntimeURLDoesNotChangeStableFileIdentity() async throws {
            let digest = String(repeating: "b", count: 64)
            let hasher = SpyContentHasher(result: .success(digest))
            let metadata = TrainingVideoMetadata(
                recordedStartAt: Date(timeIntervalSince1970: 100),
                duration: 60,
            )
            let firstURL = URL(fileURLWithPath: "/tmp/runtime-copy-a.mov")
            let secondURL = URL(fileURLWithPath: "/tmp/runtime-copy-b.mov")

            let first = try await TrainingVideoLoadingService<PhotosPickerItem>.makeReviewIdentifiedVideo(
                runtimeID: firstURL.absoluteString,
                photoLibraryIdentifier: nil,
                temporaryFileURL: firstURL,
                metadata: metadata,
                contentHasher: hasher,
            )
            let second = try await TrainingVideoLoadingService<PhotosPickerItem>.makeReviewIdentifiedVideo(
                runtimeID: secondURL.absoluteString,
                photoLibraryIdentifier: nil,
                temporaryFileURL: secondURL,
                metadata: metadata,
                contentHasher: hasher,
            )

            XCTAssertNotEqual(first.id, second.id)
            XCTAssertEqual(first.reviewSourceIdentity, second.reviewSourceIdentity)
            XCTAssertEqual(hasher.callCount, 2)
        }

        func testPickedFileHashFailureRemovesRuntimeCopyAndReturnsNoVideo() async {
            let url = URL(fileURLWithPath: "/tmp/runtime-copy.mov")
            let hasher = SpyContentHasher(result: .failure(TestError.readFailed))
            let removals = URLRemovalRecorder()

            await XCTAssertThrowsErrorAsync(
                try await TrainingVideoLoadingService<PhotosPickerItem>.makePickedReviewVideo(
                    url: url,
                    metadata: TrainingVideoMetadata(
                        recordedStartAt: Date(timeIntervalSince1970: 100),
                        duration: 60,
                    ),
                    contentHasher: hasher,
                    removeTemporaryVideo: removals.record,
                ),
            ) {
                XCTAssertEqual($0 as? TestError, .readFailed)
            }
            XCTAssertEqual(hasher.callCount, 1)
            XCTAssertEqual(removals.urls, [url])
        }

        private func makeService(
            assetIdentifier: @escaping (String) -> String? = { item in item == "photo" ? "asset-id" : nil },
            loadPhotoLibraryVideo: @escaping (String) async throws -> LoadedTrainingVideo,
            loadPickedVideo: @escaping (String) async throws -> LoadedTrainingVideo,
            ensureReady: @escaping (SelectedTrainingVideo) async throws -> Void = { _ in },
            removeTemporaryVideoIfNeeded: @escaping (SelectedTrainingVideo) -> Void = { _ in },
        ) -> TrainingVideoLoadingService<String> {
            TrainingVideoLoadingService<String>(
                assetIdentifier: assetIdentifier,
                loadPhotoLibraryVideo: loadPhotoLibraryVideo,
                loadPickedVideo: loadPickedVideo,
                ensureReady: ensureReady,
                removeTemporaryVideoIfNeeded: removeTemporaryVideoIfNeeded,
            )
        }

        private func makeSession() -> TrainingSession {
            TrainingSession(
                startedAt: Date(timeIntervalSince1970: 90),
                endedAt: Date(timeIntervalSince1970: 150),
                events: [
                    ShotMarkerEvent(markedAt: Date(timeIntervalSince1970: 120)),
                ],
            )
        }
    }

    private nonisolated final class SpyContentHasher: HighlightClipReviewContentHashing, @unchecked Sendable {
        private let lock = NSLock()
        private let result: Result<String, TestError>
        private var calls = 0

        init(result: Result<String, TestError>) {
            self.result = result
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }

        func sha256(for _: URL) async throws -> String {
            try recordCall().get()
        }

        private func recordCall() -> Result<String, TestError> {
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            return result
        }
    }

    private nonisolated final class URLRemovalRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [URL] = []

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }

        func record(_ url: URL) {
            lock.lock()
            values.append(url)
            lock.unlock()
        }
    }

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ errorHandler: (Error) -> Void = { _ in },
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected async expression to throw")
        } catch {
            errorHandler(error)
        }
    }

    private enum TestError: Error, Equatable {
        case readFailed
        case unexpectedHash
    }
#endif

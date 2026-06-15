#if os(iOS)
    @testable import ShotMarker
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
#endif

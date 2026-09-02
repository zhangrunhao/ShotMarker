@testable import ShotMarker
import AVFoundation
import XCTest

final class HighlightClipReviewViewModelTests: XCTestCase {
    @MainActor
    func testExcludeRestoreAndRangeEditsKeepStableCardIdentity() throws {
        let viewModel = makeViewModel()
        let id = viewModel.items[0].id

        try viewModel.apply(.moveBy(0.5), itemID: id)
        viewModel.setIncluded(false, itemID: id)
        viewModel.setIncluded(true, itemID: id)

        XCTAssertEqual(viewModel.items[0].id, id)
        XCTAssertEqual(viewModel.items[0].start, 0.5)
        XCTAssertTrue(viewModel.items[0].isIncluded)
        XCTAssertTrue(viewModel.hasUserChanges)
    }

    @MainActor
    func testRestoreDefaultOnlyChangesCurrentCardRangeAndNotInclusion() throws {
        let viewModel = makeViewModel(itemCount: 2)
        let firstID = viewModel.items[0].id
        let secondBefore = viewModel.items[1]
        try viewModel.apply(.moveBy(1), itemID: firstID)
        viewModel.setIncluded(false, itemID: firstID)

        viewModel.restoreDefault(itemID: firstID)

        XCTAssertEqual(viewModel.items[0].range, viewModel.items[0].defaultRange)
        XCTAssertFalse(viewModel.items[0].isIncluded)
        XCTAssertEqual(viewModel.items[1], secondBefore)
    }

    @MainActor
    func testNoIncludedOrIncludedUnavailableCardDisablesConfirmation() {
        let viewModel = makeViewModel()
        let id = viewModel.items[0].id

        viewModel.setIncluded(false, itemID: id)
        XCTAssertFalse(viewModel.canConfirm)

        viewModel.setIncluded(true, itemID: id)
        viewModel.markSourceUnavailable(itemID: id)
        XCTAssertFalse(viewModel.canConfirm)

        viewModel.setIncluded(false, itemID: id)
        XCTAssertFalse(viewModel.canConfirm)
    }

    @MainActor
    func testThumbnailFailureShowsPlaceholderWithoutMarkingSourceUnavailable() async {
        let viewModel = makeViewModel(frameResults: [.failure(TestError.frameFailed)])
        let id = viewModel.items[0].id

        await viewModel.loadThumbnail(
            itemID: id,
            targetSize: .init(width: 200, height: 120),
        )

        XCTAssertEqual(viewModel.thumbnailStates[id], .placeholder)
        XCTAssertFalse(viewModel.unavailableItemIDs.contains(id))
        XCTAssertTrue(viewModel.canConfirm)
    }

    @MainActor
    func testEditedRangeRefreshesMidpointThumbnailWithoutClearingPreviousImage() async throws {
        let viewModel = makeViewModel(
            frameResults: [.success(Data([1])), .success(Data([2]))],
        )
        let id = viewModel.items[0].id
        await viewModel.loadThumbnail(
            itemID: id,
            targetSize: .init(width: 200, height: 120),
        )

        try viewModel.apply(.moveBy(1), itemID: id)
        let refresh = Task {
            await viewModel.loadThumbnail(
                itemID: id,
                targetSize: .init(width: 200, height: 120),
            )
        }

        XCTAssertEqual(viewModel.thumbnailStates[id], .loaded(Data([1])))
        await refresh.value
        XCTAssertEqual(viewModel.thumbnailStates[id], .loaded(Data([2])))
    }

    @MainActor
    func testSubmitUsesCurrentSummarySegmentsAndPreservesDraftOnFailure() async throws {
        var submitted: [ConfirmedHighlightSegment] = []
        let viewModel = makeViewModel { segments in
            submitted = segments
            throw TestError.submitFailed
        }
        let originalItems = viewModel.items

        await viewModel.submit()

        XCTAssertEqual(submitted, viewModel.summary.finalSegments)
        XCTAssertEqual(viewModel.items, originalItems)
        XCTAssertEqual(viewModel.submissionErrorMessage, "submitFailed")
        XCTAssertFalse(viewModel.isSubmitting)
    }

    @MainActor
    func testSummaryRefreshesAfterEveryIncludeAndRangeChange() throws {
        let viewModel = makeViewModel(itemCount: 2)
        XCTAssertEqual(viewModel.summary.includedMarkerCount, 2)
        XCTAssertEqual(viewModel.summary.excludedMarkerCount, 0)
        XCTAssertEqual(viewModel.summary.finalSegmentCount, 2)
        XCTAssertEqual(viewModel.summary.totalDuration, 4)

        viewModel.setIncluded(false, itemID: viewModel.items[1].id)
        XCTAssertEqual(viewModel.summary.includedMarkerCount, 1)
        XCTAssertEqual(viewModel.summary.excludedMarkerCount, 1)
        XCTAssertEqual(viewModel.summary.finalSegmentCount, 1)
        XCTAssertEqual(viewModel.summary.totalDuration, 2)

        try viewModel.apply(.setEnd(3), itemID: viewModel.items[0].id)
        XCTAssertEqual(viewModel.summary.includedMarkerCount, 1)
        XCTAssertEqual(viewModel.summary.excludedMarkerCount, 1)
        XCTAssertEqual(viewModel.summary.finalSegmentCount, 1)
        XCTAssertEqual(viewModel.summary.totalDuration, 3)
    }

    @MainActor
    func testOpeningAnotherEditorKeepsDraftAndChangesOnlyEditingID() {
        let viewModel = makeViewModel(itemCount: 2)
        let originalItems = viewModel.items

        viewModel.openEditor(itemID: viewModel.items[0].id)
        XCTAssertEqual(viewModel.editingItemID, viewModel.items[0].id)
        viewModel.openEditor(itemID: viewModel.items[1].id)

        XCTAssertEqual(viewModel.editingItemID, viewModel.items[1].id)
        XCTAssertEqual(viewModel.items, originalItems)
    }

    @MainActor
    func testVideoIdentityDurationOrBeforeAfterChangeRequiresInvalidation() {
        let viewModel = makeViewModel()
        let video = makeVideo()
        let settings = ClipSettings.default

        XCTAssertTrue(viewModel.requiresInvalidation(
            videos: [makeVideo(id: "other")],
            clipSettings: settings,
        ))
        XCTAssertTrue(viewModel.requiresInvalidation(
            videos: [
                SelectedTrainingVideo(
                    id: video.id,
                    recordedStartAt: video.recordedStartAt.addingTimeInterval(1),
                    duration: video.duration,
                ),
            ],
            clipSettings: settings,
        ))
        XCTAssertTrue(viewModel.requiresInvalidation(
            videos: [
                SelectedTrainingVideo(
                    id: video.id,
                    recordedStartAt: video.recordedStartAt,
                    duration: video.duration + 1,
                ),
            ],
            clipSettings: settings,
        ))
        XCTAssertTrue(viewModel.requiresInvalidation(
            videos: [video],
            clipSettings: ClipSettings(
                secondsBeforeMarker: settings.secondsBeforeMarker + 1,
                secondsAfterMarker: settings.secondsAfterMarker,
            ),
        ))
        XCTAssertTrue(viewModel.requiresInvalidation(
            videos: [video],
            clipSettings: ClipSettings(
                secondsBeforeMarker: settings.secondsBeforeMarker,
                secondsAfterMarker: settings.secondsAfterMarker + 1,
            ),
        ))
    }

    @MainActor
    func testMarkerLabelStyleOnlyChangeDoesNotRequireInvalidation() {
        let viewModel = makeViewModel()
        let settings = ClipSettings.default
        let changedStyle = MarkerLabelStyle(
            fontSizeRatio: 0.2,
            normalizedCenterX: 0.8,
            normalizedCenterY: 0.7,
            textOpacity: 0.5,
            backgroundOpacity: 0.3,
        )

        XCTAssertFalse(viewModel.requiresInvalidation(
            videos: [makeVideo()],
            clipSettings: ClipSettings(
                secondsBeforeMarker: settings.secondsBeforeMarker,
                secondsAfterMarker: settings.secondsAfterMarker,
                markerLabelStyle: changedStyle,
            ),
        ))
    }

    @MainActor
    func testReturningFromEditorAndSettingsKeepsSameDraftValues() throws {
        let viewModel = makeViewModel(itemCount: 2)
        let firstID = viewModel.items[0].id
        let secondID = viewModel.items[1].id
        try viewModel.apply(.replace(start: 6, duration: 3), itemID: firstID)
        viewModel.setIncluded(false, itemID: secondID)
        let expectedItems = viewModel.items

        viewModel.openEditor(itemID: firstID)
        viewModel.closeEditor()
        XCTAssertFalse(viewModel.requiresInvalidation(
            videos: [makeVideo()],
            clipSettings: ClipSettings(
                secondsBeforeMarker: ClipSettings.default.secondsBeforeMarker,
                secondsAfterMarker: ClipSettings.default.secondsAfterMarker,
                markerLabelStyle: MarkerLabelStyle(
                    fontSizeRatio: 0.2,
                    normalizedCenterX: 0.75,
                    normalizedCenterY: 0.25,
                    textOpacity: 0.8,
                    backgroundOpacity: 0.4,
                ),
            ),
        ))
        viewModel.openEditor(itemID: firstID)

        XCTAssertEqual(viewModel.items, expectedItems)
        XCTAssertEqual(viewModel.editingItemID, firstID)
    }

    @MainActor
    func testFingerprintTreatsVideoOrderAsPlanningInput() {
        let firstVideo = makeVideo(id: "first")
        let secondVideo = SelectedTrainingVideo(
            id: "second",
            recordedStartAt: firstVideo.recordedStartAt,
            duration: firstVideo.duration,
        )
        let mediaProvider = HighlightClipReviewMediaProvider(
            cacheLimit: 0,
            loadAsset: { _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov")) },
            generateFrame: { _, _ in Data() },
        )
        let viewModel = HighlightClipReviewViewModel(
            draft: HighlightClipReviewDraft(
                selectedVideoCount: 2,
                totalMarkerCount: 0,
                items: [],
            ),
            videos: [firstVideo, secondVideo],
            clipSettings: .default,
            mediaProvider: mediaProvider,
            submitSegments: { _ in },
        )

        XCTAssertTrue(viewModel.requiresInvalidation(
            videos: [secondVideo, firstVideo],
            clipSettings: .default,
        ))
    }

    @MainActor
    func testConfirmedSegmentsReturnsTheAlreadyDisplayedSummaryArray() throws {
        let viewModel = makeViewModel(itemCount: 2)
        viewModel.setIncluded(false, itemID: viewModel.items[1].id)
        let displayed = viewModel.summary.finalSegments

        XCTAssertEqual(try viewModel.confirmedSegments(), displayed)
    }

    @MainActor
    func testDuplicateSubmitWhileSubmittingCallsClosureOnce() async {
        let started = expectation(description: "submission started")
        let gate = SubmitGate()
        var callCount = 0
        let viewModel = makeViewModel { _ in
            callCount += 1
            started.fulfill()
            await gate.wait()
        }
        let firstSubmit = Task { await viewModel.submit() }
        await fulfillment(of: [started], timeout: 1)

        await viewModel.submit()

        XCTAssertEqual(callCount, 1)
        await gate.release()
        await firstSubmit.value
    }

    @MainActor
    func testStartEndAndMoveFineTuneUseExactlyHalfSecond() throws {
        let startViewModel = makeViewModel()
        let startID = startViewModel.items[0].id
        try startViewModel.apply(.replace(start: 5, duration: 4), itemID: startID)
        try startViewModel.adjustStart(itemID: startID, by: -0.5)
        XCTAssertEqual(startViewModel.items[0].range, .init(start: 4.5, duration: 4.5))

        let endViewModel = makeViewModel()
        let endID = endViewModel.items[0].id
        try endViewModel.apply(.replace(start: 5, duration: 4), itemID: endID)
        try endViewModel.adjustEnd(itemID: endID, by: 0.5)
        XCTAssertEqual(endViewModel.items[0].range, .init(start: 5, duration: 4.5))

        let moveViewModel = makeViewModel()
        let moveID = moveViewModel.items[0].id
        try moveViewModel.apply(.replace(start: 5, duration: 4), itemID: moveID)
        try moveViewModel.moveRange(itemID: moveID, by: 0.5)
        XCTAssertEqual(moveViewModel.items[0].range, .init(start: 5.5, duration: 4))
    }

    @MainActor
    func testPlayheadPreviewDoesNotMutateRange() async throws {
        let viewModel = makeViewModel()
        let itemID = viewModel.items[0].id
        try viewModel.apply(.replace(start: 5, duration: 4), itemID: itemID)
        let originalItem = viewModel.items[0]
        let engine = ReviewTimelineSpyPlaybackEngine()
        let playbackController = HighlightClipPlaybackController(
            engine: engine,
            loadAsset: { _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov")) },
        )
        await playbackController.load(video: makeVideo(), range: originalItem.range)
        engine.resetSeekHistory()

        try await viewModel.handleTimelineAction(
            .preview(6.5),
            itemID: itemID,
            playbackController: playbackController,
        )

        XCTAssertEqual(viewModel.items[0], originalItem)
        XCTAssertEqual(engine.seekedTimes, [6.5])
    }

    @MainActor
    func testFilmstripRefreshCancelsPreviousWindowRequest() async {
        let firstStarted = expectation(description: "first filmstrip request started")
        let firstCancelled = expectation(description: "first filmstrip request cancelled")
        var didCancelFirstRequest = false
        let mediaProvider = HighlightClipReviewMediaProvider(
            cacheLimit: 8,
            loadAsset: { _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov")) },
            generateFrame: { _, request in
                if request.time < 20 {
                    firstStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch {
                        didCancelFirstRequest = true
                        firstCancelled.fulfill()
                        throw error
                    }
                    return Data([1])
                }
                return Data([2])
            },
        )
        let viewModel = makeViewModel(mediaProvider: mediaProvider)
        let itemID = viewModel.items[0].id
        let firstWindow = HighlightClipTimelineWindow(start: 0, duration: 20)
        let secondWindow = HighlightClipTimelineWindow(start: 20, duration: 20)
        let firstLoad = Task {
            await viewModel.loadFilmstrip(
                itemID: itemID,
                window: firstWindow,
                count: 1,
                targetSize: .init(width: 160, height: 90),
            )
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        await viewModel.loadFilmstrip(
            itemID: itemID,
            window: secondWindow,
            count: 1,
            targetSize: .init(width: 160, height: 90),
        )
        await fulfillment(of: [firstCancelled], timeout: 1)
        await firstLoad.value

        XCTAssertTrue(didCancelFirstRequest)
        XCTAssertEqual(viewModel.filmstripFramesByItemID[itemID], [Data([2])])
        XCTAssertEqual(viewModel.filmstripWindowsByItemID[itemID], secondWindow)
    }

    @MainActor
    func testUnavailableIncludedCardCanBeExcludedAndThenOtherCardsSubmit() async {
        var submitted: [ConfirmedHighlightSegment] = []
        let viewModel = makeViewModel(itemCount: 2) { segments in
            submitted = segments
        }
        let unavailableID = viewModel.items[0].id
        let remainingID = viewModel.items[1].id
        viewModel.markSourceUnavailable(itemID: unavailableID)
        XCTAssertFalse(viewModel.canConfirm)

        viewModel.setIncluded(false, itemID: unavailableID)
        XCTAssertTrue(viewModel.canConfirm)
        await viewModel.submit()

        XCTAssertEqual(submitted.count, 1)
        XCTAssertEqual(submitted[0].id, remainingID)
    }

    @MainActor
    private func makeViewModel(
        itemCount: Int = 1,
        frameResults: [Result<Data, TestError>] = [.success(Data([1]))],
        mediaProvider injectedMediaProvider: HighlightClipReviewMediaProvider? = nil,
        submitSegments: @escaping ([ConfirmedHighlightSegment]) async throws -> Void = { _ in },
    ) -> HighlightClipReviewViewModel {
        var nextFrameIndex = 0
        let video = makeVideo()
        let mediaProvider = injectedMediaProvider
            ?? HighlightClipReviewMediaProvider(
                cacheLimit: 8,
                loadAsset: { _ in AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov")) },
                generateFrame: { _, _ in
                    defer { nextFrameIndex += 1 }
                    return try frameResults[min(nextFrameIndex, frameResults.count - 1)].get()
                },
            )
        let items = (0 ..< itemCount).map { index in
            let number = index + 1
            let markerID = UUID(
                uuidString: String(format: "00000000-0000-0000-0000-%012d", 70_100 + number),
            )!
            return HighlightClipReviewItem(
                id: UUID(
                    uuidString: String(format: "00000000-0000-0000-0000-%012d", 70_000 + number),
                )!,
                videoID: video.id,
                markerReferences: [
                    HighlightClipMarkerReference(
                        id: markerID,
                        markedAt: Date(timeIntervalSince1970: 110 + Double(index * 5)),
                        timeInVideo: 10 + Double(index * 5),
                        originalMatchedNumber: number,
                    ),
                ],
                defaultStart: Double(index * 5),
                defaultDuration: 2,
                start: Double(index * 5),
                duration: 2,
                isIncluded: true,
            )
        }
        return HighlightClipReviewViewModel(
            draft: HighlightClipReviewDraft(
                selectedVideoCount: 1,
                totalMarkerCount: itemCount,
                items: items,
            ),
            videos: [video],
            clipSettings: .default,
            mediaProvider: mediaProvider,
            submitSegments: submitSegments,
        )
    }

    private func makeVideo(id: String = "video") -> SelectedTrainingVideo {
        SelectedTrainingVideo(
            id: id,
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
        )
    }
}

@MainActor
private final class ReviewTimelineSpyPlaybackEngine: HighlightClipPlaybackEngine {
    let player = AVPlayer()
    private(set) var seekedTimes: [TimeInterval] = []

    func replaceCurrentItem(with _: AVAsset) {}
    func clearCurrentItem() {}
    func play() {}
    func pause() {}

    func seek(to seconds: TimeInterval) async {
        seekedTimes.append(seconds)
    }

    func addPeriodicTimeObserver(_: @escaping (TimeInterval) -> Void) -> Any {
        UUID()
    }

    func addBoundaryTimeObserver(
        at _: TimeInterval,
        _: @escaping () -> Void,
    ) -> Any {
        UUID()
    }

    func removeTimeObserver(_: Any) {}

    func resetSeekHistory() {
        seekedTimes.removeAll()
    }
}

private enum TestError: LocalizedError {
    case frameFailed
    case submitFailed

    var errorDescription: String? { String(describing: self) }
}

private actor SubmitGate {
    private var isReleased = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isReleased else {
            return
        }

        await withCheckedContinuation { continuation in
            if isReleased {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

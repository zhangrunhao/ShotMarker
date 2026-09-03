@testable import ShotMarker
import AVFoundation
import XCTest

final class HighlightClipReviewViewModelTests: XCTestCase {
    @MainActor
    func testEditorChangesDoNotTouchGalleryBeforeStoreSuccess() throws {
        let fixture = makeReviewViewModelFixture()
        let originalItems = fixture.viewModel.items
        let editor = fixture.viewModel.makeEditorViewModel(itemID: originalItems[0].id)!

        try editor.moveRange(by: 1)
        editor.setIncluded(false)

        XCTAssertNotEqual(editor.workingItem, originalItems[0])
        XCTAssertEqual(fixture.viewModel.items, originalItems)
        XCTAssertEqual(fixture.viewModel.summary, fixture.originalSummary)
    }

    @MainActor
    func testDefaultItemCanBeConfirmedWithoutChangingRange() async {
        let fixture = makeReviewViewModelFixture()
        let editor = fixture.viewModel.makeEditorViewModel(
            itemID: fixture.viewModel.items[0].id,
        )!

        let navigation = await editor.confirm()

        let upsertCount = await fixture.store.upsertCount
        XCTAssertNotNil(navigation)
        XCTAssertEqual(fixture.viewModel.items[0].confirmationState, .confirmed)
        XCTAssertEqual(upsertCount, 1)
    }

    @MainActor
    func testStoreFailureKeepsGalleryAndNavigationUnchanged() async throws {
        let fixture = makeReviewViewModelFixture(storeError: TestError.writeFailed)
        let originalItems = fixture.viewModel.items
        let editor = fixture.viewModel.makeEditorViewModel(itemID: originalItems[0].id)!
        try editor.moveRange(by: 1)

        let navigation = await editor.confirm()

        XCTAssertNil(navigation)
        XCTAssertEqual(fixture.viewModel.items, originalItems)
        XCTAssertEqual(fixture.viewModel.editingItemID, originalItems[0].id)
        XCTAssertNotNil(editor.saveErrorMessage)
    }

    @MainActor
    func testSuccessfulConfirmationNormalizesThenPersistsThenPublishes() async throws {
        let fixture = makeReviewViewModelFixture(now: Date(timeIntervalSince1970: 500))
        let firstID = fixture.viewModel.items[0].id
        let editor = fixture.viewModel.makeEditorViewModel(itemID: firstID)!
        try editor.apply(.replace(start: 10.06, duration: 2.04))

        _ = await editor.confirm()

        let persisted = await fixture.store.confirmations(for: fixture.key)
        XCTAssertEqual(persisted[0].start, 10.1)
        XCTAssertEqual(persisted[0].duration, 2.0)
        XCTAssertEqual(persisted[0].confirmedAt, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(
            fixture.viewModel.items[0].range,
            HighlightClipRange(start: 10.1, duration: 2.0),
        )
        XCTAssertEqual(fixture.viewModel.items[0].confirmationState, .confirmed)
    }

    @MainActor
    func testIncludedUnavailableSourceCannotConfirmButExcludedCan() async {
        let fixture = makeReviewViewModelFixture(sourceError: .sourceUnavailable)
        let itemID = fixture.viewModel.items[0].id
        fixture.viewModel.markSourceUnavailable(itemID: itemID)
        let included = fixture.viewModel.makeEditorViewModel(itemID: itemID)!

        let includedNavigation = await included.confirm()
        let beforeExclusionCount = await fixture.store.upsertCount
        XCTAssertNil(includedNavigation)
        XCTAssertEqual(beforeExclusionCount, 0)

        included.setIncluded(false)
        let excludedNavigation = await included.confirm()
        let afterExclusionCount = await fixture.store.upsertCount
        XCTAssertNotNil(excludedNavigation)
        XCTAssertEqual(afterExclusionCount, 1)
        XCTAssertFalse(fixture.viewModel.items[0].isIncluded)
    }

    @MainActor
    func testConfirmationSkipsConfirmedCardsAndOpensFirstLaterDefault() async {
        let fixture = makeReviewViewModelFixture(
            states: [.defaultValue, .confirmed, .defaultValue],
        )
        let editor = fixture.viewModel.makeEditorViewModel(
            itemID: fixture.viewModel.items[0].id,
        )!

        let navigation = await editor.confirm()

        XCTAssertEqual(navigation, .open(itemID: fixture.viewModel.items[2].id))
    }

    @MainActor
    func testConfirmationAfterLastLaterDefaultReturnsToReviewWithoutLooping() async {
        let fixture = makeReviewViewModelFixture(
            states: [.defaultValue, .confirmed, .confirmed],
        )
        let editor = fixture.viewModel.makeEditorViewModel(
            itemID: fixture.viewModel.items[0].id,
        )!

        let navigation = await editor.confirm()

        XCTAssertEqual(navigation, .returnToReview)
        XCTAssertNil(fixture.viewModel.editingItemID)
    }

    @MainActor
    func testPageSubmissionAcceptsMixedConfirmedAndDefaultItems() async {
        let submitter = SegmentRecorder()
        let fixture = makeReviewViewModelFixture(
            states: [.confirmed, .defaultValue],
            submitSegments: { segments in
                await submitter.submit(segments)
            },
        )

        XCTAssertTrue(fixture.viewModel.canConfirm)
        await fixture.viewModel.submit()
        let callCount = await submitter.callCount
        let lastMarkerIDs = await submitter.lastSegments.flatMap(\.markerIDs)

        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(
            Set(lastMarkerIDs),
            Set(
                fixture.viewModel.items
                    .filter(\.isIncluded)
                    .flatMap(\.markerReferences)
                    .map(\.id),
            ),
        )
    }

    @MainActor
    func testRecoveryNoticesAreNonBlockingAndDoNotDisableSubmission() {
        let corrupt = makeReviewViewModelFixture(
            recoveryNoticeMessage: "已恢复损坏的片段确认文件，当前使用默认范围。",
        )
        let partial = makeReviewViewModelFixture(
            recoveryNoticeMessage: "部分已保存片段无法恢复，已使用默认范围。",
        )
        let future = makeReviewViewModelFixture(
            recoveryNoticeMessage: "片段确认数据来自更新版本，当前使用默认范围；更新 App 后才能保存新的片段确认。",
        )

        XCTAssertTrue(corrupt.viewModel.canConfirm)
        XCTAssertTrue(partial.viewModel.canConfirm)
        XCTAssertTrue(future.viewModel.canConfirm)
        XCTAssertNotNil(corrupt.viewModel.recoveryNoticeMessage)
        XCTAssertNotNil(partial.viewModel.recoveryNoticeMessage)
        XCTAssertNotNil(future.viewModel.recoveryNoticeMessage)
    }

    @MainActor
    func testRecreatedReviewRestoresSameOrderAndReplansDefaultsForNewSettings() async throws {
        let fixture = makeReviewFlowFixture()
        let key = try HighlightClipReviewIdentityBuilder.combinationKey(
            for: fixture.session,
            videos: fixture.videos,
        )
        let first = fixture.makeViewModel(key: key)
        let editor = first.makeEditorViewModel(itemID: first.items[0].id)!
        try editor.moveRange(by: 1)
        _ = await editor.confirm()

        let loaded = try await fixture.store.loadRecord(for: key)
        var changedSettings = fixture.settings
        changedSettings.secondsBeforeMarker = 2
        changedSettings.secondsAfterMarker = 2
        let restored = HighlightClipReviewPlanner.restoreDraft(
            for: fixture.session,
            videos: fixture.videos,
            clipSettings: changedSettings,
            persistedRecord: loaded.record,
        )
        let recreated = fixture.makeViewModel(
            draft: restored.draft,
            key: key,
            settings: changedSettings,
        )

        XCTAssertNil(recreated.editingItemID)
        XCTAssertEqual(recreated.items[0].confirmationState, .confirmed)
        XCTAssertEqual(recreated.items[0].range, first.items[0].range)
        XCTAssertNotEqual(
            recreated.items.filter { $0.confirmationState == .defaultValue }.map(\.range),
            first.items.filter { $0.confirmationState == .defaultValue }.map(\.range),
        )
    }

    @MainActor
    func testReversedVideoOrderDoesNotLoadOriginalCombinationRecord() async throws {
        let fixture = makeReviewFlowFixture()
        let originalKey = try HighlightClipReviewIdentityBuilder.combinationKey(
            for: fixture.session,
            videos: fixture.videos,
        )
        try await fixture.store.upsert(
            fixture.confirmation,
            for: originalKey,
            now: fixture.now,
        )
        let reversedKey = try HighlightClipReviewIdentityBuilder.combinationKey(
            for: fixture.session,
            videos: Array(fixture.videos.reversed()),
        )

        let reversedLoad = try await fixture.store.loadRecord(for: reversedKey)

        XCTAssertNil(reversedLoad.record)
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

        let editor = viewModel.makeEditorViewModel(itemID: id)!
        try editor.moveRange(by: 1)
        _ = await editor.confirm()
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
    func testCreatingAnotherEditorKeepsGalleryAndChangesOnlyEditingID() {
        let viewModel = makeViewModel(itemCount: 2)
        let originalItems = viewModel.items

        XCTAssertNotNil(viewModel.makeEditorViewModel(itemID: viewModel.items[0].id))
        XCTAssertEqual(viewModel.editingItemID, viewModel.items[0].id)
        XCTAssertNotNil(viewModel.makeEditorViewModel(itemID: viewModel.items[1].id))

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
                    reviewSourceIdentity: video.reviewSourceIdentity,
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
                    reviewSourceIdentity: video.reviewSourceIdentity,
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

    func testPreparationSnapshotRejectsInvalidatedRevisionBeforeNewVideosFinishLoading() {
        let revision = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let snapshot = HighlightClipReviewPreparationSnapshot(
            videos: [makeVideo()],
            clipSettings: .default,
            revision: revision,
        )

        XCTAssertFalse(snapshot.matches(
            videos: [makeVideo()],
            clipSettings: .default,
            revision: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!,
        ))
    }

    func testPreparationSnapshotRejectsChangedVideoOrderOrRange() {
        let revision = UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
        let firstVideo = makeVideo(id: "first")
        let secondVideo = makeVideo(id: "second")
        let snapshot = HighlightClipReviewPreparationSnapshot(
            videos: [firstVideo, secondVideo],
            clipSettings: .default,
            revision: revision,
        )
        var changedRange = ClipSettings.default
        changedRange.secondsBeforeMarker += 1

        XCTAssertFalse(snapshot.matches(
            videos: [secondVideo, firstVideo],
            clipSettings: .default,
            revision: revision,
        ))
        XCTAssertFalse(snapshot.matches(
            videos: [firstVideo, secondVideo],
            clipSettings: changedRange,
            revision: revision,
        ))
    }

    func testPreparationSnapshotAllowsMarkerLabelStyleOnlyChange() {
        let revision = UUID(uuidString: "00000000-0000-0000-0000-000000000904")!
        let video = makeVideo()
        let snapshot = HighlightClipReviewPreparationSnapshot(
            videos: [video],
            clipSettings: .default,
            revision: revision,
        )
        var changedStyle = ClipSettings.default
        changedStyle.markerLabelStyle = MarkerLabelStyle(
            fontSizeRatio: 0.2,
            normalizedCenterX: 0.8,
            normalizedCenterY: 0.7,
            textOpacity: 0.5,
            backgroundOpacity: 0.3,
        )

        XCTAssertTrue(snapshot.matches(
            videos: [video],
            clipSettings: changedStyle,
            revision: revision,
        ))
    }

    @MainActor
    func testFingerprintTreatsVideoOrderAsPlanningInput() {
        let firstVideo = makeVideo(id: "first")
        let secondVideo = SelectedTrainingVideo(
            id: "second",
            recordedStartAt: firstVideo.recordedStartAt,
            duration: firstVideo.duration,
            reviewSourceIdentity: .photoLibraryAsset("legacy-test-asset-second"),
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
            combinationKey: try! HighlightClipReviewIdentityBuilder.combinationKey(
                for: TrainingSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000698")!,
                    startedAt: firstVideo.recordedStartAt,
                    endedAt: firstVideo.recordedEndAt,
                    events: [],
                ),
                videos: [firstVideo, secondVideo],
            ),
            reviewStore: InMemoryHighlightClipReviewStore(),
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
        let viewModel = makeViewModel(
            itemCount: 2,
            states: [.confirmed, .defaultValue],
        )
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
    func testSubmitRevalidatesIncludedSourceWithoutTrustingCachedAsset() async {
        var sourceIsAvailable = true
        var assetLoadCount = 0
        var submitted: [ConfirmedHighlightSegment] = []
        let mediaProvider = HighlightClipReviewMediaProvider(
            cacheLimit: 8,
            loadAsset: { _ in
                assetLoadCount += 1
                guard sourceIsAvailable else {
                    throw HighlightClipReviewMediaError.sourceUnavailable
                }
                return AVURLAsset(url: URL(fileURLWithPath: "/tmp/video.mov"))
            },
            generateFrame: { _, _ in Data([1]) },
        )
        let viewModel = makeViewModel(mediaProvider: mediaProvider) { segments in
            submitted = segments
        }
        let itemID = viewModel.items[0].id

        await viewModel.loadThumbnail(
            itemID: itemID,
            targetSize: .init(width: 160, height: 90),
        )
        XCTAssertEqual(assetLoadCount, 1)

        sourceIsAvailable = false
        await viewModel.submit()

        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(assetLoadCount, 2)
        XCTAssertTrue(viewModel.unavailableItemIDs.contains(itemID))
        XCTAssertEqual(
            viewModel.submissionErrorMessage,
            HighlightClipReviewMediaError.sourceUnavailable.errorDescription,
        )
    }

    @MainActor
    private func makeViewModel(
        itemCount: Int = 1,
        states: [HighlightClipConfirmationState]? = nil,
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
                confirmationState: states?[index] ?? .defaultValue,
            )
        }
        let session = TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000699")!,
            startedAt: video.recordedStartAt,
            endedAt: video.recordedEndAt,
            events: items.flatMap(\.markerReferences).map {
                ShotMarkerEvent(id: $0.id, markedAt: $0.markedAt)
            },
        )
        let key = try! HighlightClipReviewIdentityBuilder.combinationKey(
            for: session,
            videos: [video],
        )
        return HighlightClipReviewViewModel(
            draft: HighlightClipReviewDraft(
                selectedVideoCount: 1,
                totalMarkerCount: itemCount,
                items: items,
            ),
            videos: [video],
            clipSettings: .default,
            combinationKey: key,
            reviewStore: InMemoryHighlightClipReviewStore(),
            mediaProvider: mediaProvider,
            submitSegments: submitSegments,
        )
    }

    private func makeVideo(id: String = "video") -> SelectedTrainingVideo {
        SelectedTrainingVideo(
            id: id,
            recordedStartAt: Date(timeIntervalSince1970: 100),
            duration: 60,
            reviewSourceIdentity: .photoLibraryAsset("legacy-test-asset-\(id)"),
        )
    }
}

@MainActor
private struct ReviewViewModelFixture {
    let viewModel: HighlightClipReviewViewModel
    let store: InMemoryHighlightClipReviewStore
    let key: HighlightClipReviewCombinationKey
    let originalSummary: HighlightClipReviewSummary
}

@MainActor
private func makeReviewViewModelFixture(
    states: [HighlightClipConfirmationState] = [
        .defaultValue,
        .defaultValue,
        .defaultValue,
    ],
    storeError: TestError? = nil,
    sourceError: HighlightClipReviewMediaError? = nil,
    now: Date = Date(timeIntervalSince1970: 400),
    recoveryNoticeMessage: String? = nil,
    submitSegments: @escaping HighlightClipReviewViewModel.SubmitSegments = { _ in },
) -> ReviewViewModelFixture {
    let video = SelectedTrainingVideo(
        id: "review-runtime-video",
        recordedStartAt: Date(timeIntervalSince1970: 100),
        duration: 60,
        reviewSourceIdentity: .photoLibraryAsset("review-asset"),
    )
    let events = states.indices.map { index in
        ShotMarkerEvent(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    60_100 + index,
                ),
            )!,
            markedAt: Date(timeIntervalSince1970: 110 + Double(index * 10)),
        )
    }
    let session = TrainingSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000600")!,
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 160),
        events: events,
    )
    let items = zip(events.indices, states).map { index, state in
        let event = events[index]
        return HighlightClipReviewItem(
            id: event.id,
            videoID: video.id,
            markerReferences: [
                HighlightClipMarkerReference(
                    id: event.id,
                    markedAt: event.markedAt,
                    timeInVideo: event.markedAt.timeIntervalSince(video.recordedStartAt),
                    originalMatchedNumber: index + 1,
                ),
            ],
            defaultStart: 10 + Double(index * 10),
            defaultDuration: 2,
            start: 10 + Double(index * 10),
            duration: 2,
            isIncluded: true,
            confirmationState: state,
        )
    }
    let key = try! HighlightClipReviewIdentityBuilder.combinationKey(
        for: session,
        videos: [video],
    )
    let store = InMemoryHighlightClipReviewStore(upsertError: storeError)
    let mediaProvider = HighlightClipReviewMediaProvider(
        cacheLimit: 8,
        loadAsset: { _ in
            if let sourceError {
                throw sourceError
            }
            return AVURLAsset(url: URL(fileURLWithPath: "/tmp/review-video.mov"))
        },
        generateFrame: { _, _ in Data([1]) },
    )
    let viewModel = HighlightClipReviewViewModel(
        draft: HighlightClipReviewDraft(
            selectedVideoCount: 1,
            totalMarkerCount: events.count,
            items: items,
        ),
        videos: [video],
        clipSettings: .default,
        combinationKey: key,
        reviewStore: store,
        recoveryNoticeMessage: recoveryNoticeMessage,
        mediaProvider: mediaProvider,
        now: { now },
        submitSegments: submitSegments,
    )
    return ReviewViewModelFixture(
        viewModel: viewModel,
        store: store,
        key: key,
        originalSummary: viewModel.summary,
    )
}

private struct ReviewFlowFixture {
    let session: TrainingSession
    let videos: [SelectedTrainingVideo]
    let settings: ClipSettings
    let store: InMemoryHighlightClipReviewStore
    let now: Date
    let confirmation: PersistedHighlightClipConfirmation

    @MainActor
    func makeViewModel(
        draft: HighlightClipReviewDraft? = nil,
        key: HighlightClipReviewCombinationKey,
        settings overrideSettings: ClipSettings? = nil,
    ) -> HighlightClipReviewViewModel {
        let effectiveSettings = overrideSettings ?? settings
        let effectiveDraft = draft ?? HighlightClipReviewPlanner.makeDraft(
            for: session,
            videos: videos,
            clipSettings: effectiveSettings,
        )
        return HighlightClipReviewViewModel(
            draft: effectiveDraft,
            videos: videos,
            clipSettings: effectiveSettings,
            combinationKey: key,
            reviewStore: store,
            mediaProvider: HighlightClipReviewMediaProvider(
                cacheLimit: 8,
                loadAsset: { _ in
                    AVURLAsset(url: URL(fileURLWithPath: "/tmp/review-flow.mov"))
                },
                generateFrame: { _, _ in Data([1]) },
            ),
            now: { now },
            submitSegments: { _ in },
        )
    }
}

private func makeReviewFlowFixture() -> ReviewFlowFixture {
    let firstStart = Date(timeIntervalSince1970: 100)
    let secondStart = Date(timeIntervalSince1970: 300)
    let firstMarker = ShotMarkerEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
        markedAt: Date(timeIntervalSince1970: 110),
    )
    let secondMarker = ShotMarkerEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
        markedAt: Date(timeIntervalSince1970: 140),
    )
    let firstSource = HighlightClipReviewSourceIdentity.photoLibraryAsset(
        "review-flow-asset-a",
    )
    let videos = [
        SelectedTrainingVideo(
            id: "review-flow-runtime-a",
            recordedStartAt: firstStart,
            duration: 60,
            reviewSourceIdentity: firstSource,
        ),
        SelectedTrainingVideo(
            id: "review-flow-runtime-b",
            recordedStartAt: secondStart,
            duration: 60,
            reviewSourceIdentity: .photoLibraryAsset("review-flow-asset-b"),
        ),
    ]
    let session = TrainingSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000800")!,
        startedAt: firstStart,
        endedAt: secondStart.addingTimeInterval(60),
        events: [firstMarker, secondMarker],
    )
    let now = Date(timeIntervalSince1970: 500)
    return ReviewFlowFixture(
        session: session,
        videos: videos,
        settings: .default,
        store: InMemoryHighlightClipReviewStore(),
        now: now,
        confirmation: PersistedHighlightClipConfirmation(
            videoIdentity: try! HighlightClipReviewIdentityBuilder.videoIdentity(
                for: videos[0],
            ),
            markerIDs: [firstMarker.id],
            defaultStart: 1,
            defaultDuration: 13,
            start: 1,
            duration: 13,
            isIncluded: true,
            confirmedAt: now,
        ),
    )
}

private actor SegmentRecorder {
    private(set) var callCount = 0
    private(set) var lastSegments: [ConfirmedHighlightSegment] = []

    func submit(_ segments: [ConfirmedHighlightSegment]) {
        callCount += 1
        lastSegments = segments
    }
}

private nonisolated enum TestError: LocalizedError {
    case frameFailed
    case submitFailed
    case writeFailed

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

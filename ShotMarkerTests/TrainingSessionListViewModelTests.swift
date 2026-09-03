import Combine
@testable import ShotMarker
import XCTest

final class TrainingSessionListViewModelTests: XCTestCase {
    @MainActor
    func testSuccessfulLoadReconcilesCompleteCurrentTrainingIdentities() async throws {
        let sessions = [
            try makeSession(id: "00000000-0000-0000-0000-000000000901"),
            try makeSession(id: "00000000-0000-0000-0000-000000000902"),
        ]
        let reviewStore = InMemoryHighlightClipReviewStore()
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: sessions),
            reviewStore: reviewStore,
        )

        await viewModel.load()
        let reconciled = await reviewStore.lastValidTrainingIdentities

        XCTAssertEqual(
            reconciled,
            Set(sessions.map { HighlightClipReviewIdentityBuilder.trainingIdentity(for: $0) }),
        )
    }

    @MainActor
    func testDeletingSelectionSavesTrainingFirstThenDeletesEverySelectedID() async throws {
        let first = try makeSession(id: "00000000-0000-0000-0000-000000000911")
        let second = try makeSession(id: "00000000-0000-0000-0000-000000000912")
        let trainingStore = InMemoryTrainingSessionStore(sessions: [first, second])
        let reviewStore = InMemoryHighlightClipReviewStore()
        let viewModel = TrainingSessionListViewModel(
            store: trainingStore,
            reviewStore: reviewStore,
        )
        await viewModel.load()
        viewModel.beginSelection(with: first.id)

        await viewModel.deleteSelectedSessions()
        let deletedIDs = await reviewStore.deletedTrainingSessionIDs

        XCTAssertEqual(try trainingStore.loadTrainingSessions(), [second])
        XCTAssertEqual(deletedIDs, [first.id])
    }

    @MainActor
    func testMergeDeletesReviewRecordsForEverySelectedIDIncludingRetainedID() async throws {
        let first = try makeSession(
            id: "00000000-0000-0000-0000-000000000921",
            startedAt: Date(timeIntervalSince1970: 2_000),
        )
        let second = try makeSession(
            id: "00000000-0000-0000-0000-000000000922",
            startedAt: Date(timeIntervalSince1970: 3_000),
        )
        let reviewStore = InMemoryHighlightClipReviewStore()
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [first, second]),
            reviewStore: reviewStore,
        )
        await viewModel.load()
        viewModel.beginSelection(with: first.id)
        viewModel.toggleSelection(for: second.id)

        await viewModel.mergeSelectedSessions()
        let deletedIDs = await reviewStore.deletedTrainingSessionIDs

        XCTAssertEqual(
            Set(deletedIDs),
            Set([first.id, second.id]),
        )
        XCTAssertEqual(viewModel.rows.count, 1)
    }

    func testLoadSortsTrainingSessionsNewestFirst() async throws {
        let older = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 1300),
            events: [],
        )
        let newer = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2300),
            events: [],
        )
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [older, newer]),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.id), [newer.id, older.id])
    }

    func testLoadLogsSuccessfulTrainingSessionCount() async throws {
        let first = try makeSession(id: "00000000-0000-0000-0000-000000000501")
        let second = try makeSession(id: "00000000-0000-0000-0000-000000000502")
        let logger = SpyAppLogger()
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [first, second]),
            reviewStore: InMemoryHighlightClipReviewStore(),
            logger: logger,
        )

        await viewModel.load()

        let entry = logger.entry(named: "training.sessions.load.succeeded")
        XCTAssertEqual(entry?.level, .info)
        XCTAssertEqual(entry?.category, .training)
        XCTAssertEqual(entry?.context["trainingSessionCount"], "2")
    }

    func testLoadLogsFailure() async {
        let logger = SpyAppLogger()
        let viewModel = TrainingSessionListViewModel(
            store: ThrowingTrainingSessionStore(loadError: TrainingSessionListStoreError.failed),
            reviewStore: InMemoryHighlightClipReviewStore(),
            logger: logger,
        )

        await viewModel.load()

        let entry = logger.entry(named: "training.sessions.load.failed")
        XCTAssertEqual(entry?.level, .error)
        XCTAssertEqual(entry?.category, .training)
        XCTAssertNotNil(entry?.errorDescription)
    }

    func testLoadMapsTrainingSessionStateIntoRows() async throws {
        let marker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003")),
            markedAt: Date(timeIntervalSince1970: 2100),
        )
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000004")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2300),
            events: [marker],
        )
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [session]),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.rows, [
            TrainingSessionRowViewData(
                id: session.id,
                startedAt: session.startedAt,
                titleDate: marker.markedAt,
                descriptionStartedAt: marker.markedAt,
                descriptionEndedAt: marker.markedAt,
                markerCount: 1,
            ),
        ])
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testSessionReturnsLoadedSessionForRowID() async throws {
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000005")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2300),
            events: [],
        )
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [session]),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.session(for: session.id), session)
    }

    func testLoadMapsRowTitleDateAndDescriptionRangeFromEarliestAndLatestMarkers() async throws {
        let firstMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201")),
            markedAt: Date(timeIntervalSince1970: 2200),
        )
        let lastMarker = try ShotMarkerEvent(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000202")),
            markedAt: Date(timeIntervalSince1970: 2500),
        )
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000203")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2800),
            events: [
                lastMarker,
                firstMarker,
            ],
        )
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [session]),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.first?.titleDate, firstMarker.markedAt)
        XCTAssertEqual(viewModel.rows.first?.descriptionStartedAt, firstMarker.markedAt)
        XCTAssertEqual(viewModel.rows.first?.descriptionEndedAt, lastMarker.markedAt)
    }

    func testLoadFallsBackToSessionRangeWhenRowHasNoMarkers() async throws {
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000204")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2800),
            events: [],
        )
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [session]),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.first?.titleDate, session.startedAt)
        XCTAssertEqual(viewModel.rows.first?.descriptionStartedAt, session.startedAt)
        XCTAssertEqual(viewModel.rows.first?.descriptionEndedAt, session.endedAt)
    }

    func testMergeSelectedSessionsCombinesSelectedRowsIntoOneSession() async throws {
        let firstSession = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000301")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2600),
            events: [
                ShotMarkerEvent(
                    id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000302")),
                    markedAt: Date(timeIntervalSince1970: 2400),
                ),
            ],
        )
        let secondSession = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000303")),
            startedAt: Date(timeIntervalSince1970: 3000),
            endedAt: Date(timeIntervalSince1970: 3600),
            events: [
                ShotMarkerEvent(
                    id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000304")),
                    markedAt: Date(timeIntervalSince1970: 3200),
                ),
                ShotMarkerEvent(
                    id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000305")),
                    markedAt: Date(timeIntervalSince1970: 3100),
                ),
            ],
        )
        let unselectedSession = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000306")),
            startedAt: Date(timeIntervalSince1970: 4000),
            endedAt: Date(timeIntervalSince1970: 4600),
            events: [],
        )
        let store = InMemoryTrainingSessionStore(sessions: [firstSession, secondSession, unselectedSession])
        let viewModel = TrainingSessionListViewModel(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()
        viewModel.beginSelection(with: firstSession.id)
        viewModel.toggleSelection(for: secondSession.id)
        await viewModel.mergeSelectedSessions()

        let savedSessions = try store.loadTrainingSessions()
        XCTAssertEqual(savedSessions.count, 2)
        XCTAssertFalse(viewModel.isSelectionMode)
        XCTAssertFalse(viewModel.canMergeSelectedSessions)
        XCTAssertEqual(viewModel.rows.count, 2)

        let mergedSession = try XCTUnwrap(savedSessions.first { $0.id == firstSession.id })
        XCTAssertEqual(mergedSession.startedAt, firstSession.events[0].markedAt)
        XCTAssertEqual(mergedSession.endedAt, secondSession.events[0].markedAt)
        XCTAssertEqual(mergedSession.events.map(\.markedAt), [
            firstSession.events[0].markedAt,
            secondSession.events[1].markedAt,
            secondSession.events[0].markedAt,
        ])
        XCTAssertTrue(savedSessions.contains(unselectedSession))
    }

    func testMergeRequiresAtLeastTwoSelectedSessions() async throws {
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000401")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2600),
            events: [],
        )
        let store = InMemoryTrainingSessionStore(sessions: [session])
        let viewModel = TrainingSessionListViewModel(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()
        viewModel.beginSelection(with: session.id)
        await viewModel.mergeSelectedSessions()

        XCTAssertEqual(try store.loadTrainingSessions(), [session])
        XCTAssertTrue(viewModel.isSelectionMode)
        XCTAssertFalse(viewModel.canMergeSelectedSessions)
    }

    func testSelectedSessionsForExportReturnsSelectedSessionsInVisibleRowOrder() async throws {
        let older = try makeSession(
            id: "00000000-0000-0000-0000-000000000801",
            startedAt: Date(timeIntervalSince1970: 1000),
        )
        let newer = try makeSession(
            id: "00000000-0000-0000-0000-000000000802",
            startedAt: Date(timeIntervalSince1970: 2000),
        )
        let unselected = try makeSession(
            id: "00000000-0000-0000-0000-000000000803",
            startedAt: Date(timeIntervalSince1970: 3000),
        )
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [older, newer, unselected]),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()
        viewModel.beginSelection(with: older.id)
        viewModel.toggleSelection(for: newer.id)

        XCTAssertEqual(viewModel.selectedSessionsForExport(), [newer, older])
    }

    func testAllSessionsForExportReturnsAllSessionsInVisibleRowOrder() async throws {
        let older = try makeSession(
            id: "00000000-0000-0000-0000-000000000804",
            startedAt: Date(timeIntervalSince1970: 1000),
        )
        let newer = try makeSession(
            id: "00000000-0000-0000-0000-000000000805",
            startedAt: Date(timeIntervalSince1970: 2000),
        )
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [older, newer]),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.allSessionsForExport(), [newer, older])
    }

    func testExportAllSessionsDataEncodesAllVisibleSessions() async throws {
        let older = try makeSession(
            id: "00000000-0000-0000-0000-000000000806",
            startedAt: Date(timeIntervalSince1970: 1000),
        )
        let newer = try makeSession(
            id: "00000000-0000-0000-0000-000000000807",
            startedAt: Date(timeIntervalSince1970: 2000),
        )
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [older, newer]),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()
        let data = try viewModel.exportAllSessionsData()

        XCTAssertEqual(try JSONDecoder().decode([TrainingSession].self, from: data), [newer, older])
    }

    func testTrainingSessionPressFeedbackStateTracksPressedSession() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000901"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000902"))
        var state = TrainingSessionPressFeedbackState()

        XCTAssertNil(state.pressedSessionID)
        XCTAssertFalse(state.isPressing(firstID))

        state.setPressing(firstID, isPressing: true)

        XCTAssertEqual(state.pressedSessionID, firstID)
        XCTAssertTrue(state.isPressing(firstID))
        XCTAssertFalse(state.isPressing(secondID))

        state.setPressing(secondID, isPressing: true)
        state.setPressing(firstID, isPressing: false)

        XCTAssertEqual(state.pressedSessionID, secondID)

        state.clear()

        XCTAssertNil(state.pressedSessionID)
    }

    func testTrainingSessionTitlePressFeedbackStateTracksPressing() {
        var state = TrainingSessionTitlePressFeedbackState()

        XCTAssertFalse(state.isPressing)

        state.setPressing(true)

        XCTAssertTrue(state.isPressing)

        state.setPressing(false)

        XCTAssertFalse(state.isPressing)

        state.setPressing(true)
        state.clear()

        XCTAssertFalse(state.isPressing)
    }

    func testTrainingSessionNavigationStateTracksTargetSession() throws {
        let sessionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000903"))
        var state = TrainingSessionNavigationState()

        XCTAssertNil(state.target)

        state.open(sessionID)

        XCTAssertEqual(state.target?.id, sessionID)

        state.clear()

        XCTAssertNil(state.target)
    }

    func testTrainingSessionRowPresentationUsesCompactSameDayTimeRange() throws {
        let sameDayStart = Date(timeIntervalSince1970: 1_767_355_200)
        let sameDayEnd = sameDayStart.addingTimeInterval(30 * 60)
        let row = TrainingSessionRowViewData(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000904")),
            startedAt: sameDayStart,
            titleDate: sameDayStart,
            descriptionStartedAt: sameDayStart,
            descriptionEndedAt: sameDayEnd,
            markerCount: 12,
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let presentation = TrainingSessionRowPresentation(row: row, calendar: calendar)

        XCTAssertFalse(presentation.includesDateInTimeRange)
        XCTAssertEqual(presentation.markerCountText, "12")
        XCTAssertEqual(presentation.markerUnitText, "打点")
    }

    func testTrainingSessionRowPresentationIncludesDateForCrossDayTimeRange() throws {
        let firstDay = Date(timeIntervalSince1970: 1_767_355_200)
        let nextDay = firstDay.addingTimeInterval(24 * 60 * 60)
        let row = TrainingSessionRowViewData(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000905")),
            startedAt: firstDay,
            titleDate: firstDay,
            descriptionStartedAt: firstDay,
            descriptionEndedAt: nextDay,
            markerCount: 2,
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let presentation = TrainingSessionRowPresentation(row: row, calendar: calendar)

        XCTAssertTrue(presentation.includesDateInTimeRange)
    }

    func testMergeSelectedSessionsLogsSuccess() async throws {
        let firstSession = try makeSession(id: "00000000-0000-0000-0000-000000000601")
        let secondSession = try makeSession(id: "00000000-0000-0000-0000-000000000602")
        let logger = SpyAppLogger()
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: [firstSession, secondSession]),
            reviewStore: InMemoryHighlightClipReviewStore(),
            logger: logger,
        )

        await viewModel.load()
        viewModel.beginSelection(with: firstSession.id)
        viewModel.toggleSelection(for: secondSession.id)
        await viewModel.mergeSelectedSessions()

        let entry = logger.entry(named: "training.sessions.merge.succeeded")
        XCTAssertEqual(entry?.level, .info)
        XCTAssertEqual(entry?.category, .training)
        XCTAssertEqual(entry?.context["mergedSessionCount"], "2")
        XCTAssertNil(entry?.context["trainingSessionId"])
    }

    func testMergeSelectedSessionsLogsFailure() async throws {
        let firstSession = try makeSession(id: "00000000-0000-0000-0000-000000000701")
        let secondSession = try makeSession(id: "00000000-0000-0000-0000-000000000702")
        let logger = SpyAppLogger()
        let viewModel = TrainingSessionListViewModel(
            store: ThrowingTrainingSessionStore(
                sessions: [firstSession, secondSession],
                saveError: TrainingSessionListStoreError.failed,
            ),
            reviewStore: InMemoryHighlightClipReviewStore(),
            logger: logger,
        )

        await viewModel.load()
        viewModel.beginSelection(with: firstSession.id)
        viewModel.toggleSelection(for: secondSession.id)
        await viewModel.mergeSelectedSessions()

        let entry = logger.entry(named: "training.sessions.merge.failed")
        XCTAssertEqual(entry?.level, .error)
        XCTAssertEqual(entry?.category, .training)
        XCTAssertNotNil(entry?.errorDescription)
    }

    func testLoadShowsEmptyStateWhenNoTrainingSessionsExist() async {
        let viewModel = TrainingSessionListViewModel(
            store: InMemoryTrainingSessionStore(sessions: []),
            reviewStore: InMemoryHighlightClipReviewStore(),
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testRowsRefreshWhenTrainingSessionsDidChangeNotificationIsPosted() async throws {
        let store = InMemoryTrainingSessionStore(sessions: [])
        let notificationCenter = NotificationCenter()
        let viewModel = TrainingSessionListViewModel(
            store: store,
            reviewStore: InMemoryHighlightClipReviewStore(),
            notificationCenter: notificationCenter,
        )
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101")),
            startedAt: Date(timeIntervalSince1970: 3000),
            endedAt: Date(timeIntervalSince1970: 3300),
            events: [
                ShotMarkerEvent(
                    id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102")),
                    markedAt: Date(timeIntervalSince1970: 3100),
                ),
            ],
        )
        let rowsRefreshed = expectation(description: "Rows refreshed")
        var cancellables = Set<AnyCancellable>()

        viewModel.$rows
            .dropFirst()
            .sink { rows in
                if rows.map(\.id) == [session.id] {
                    rowsRefreshed.fulfill()
                }
            }
            .store(in: &cancellables)

        await viewModel.load()
        XCTAssertTrue(viewModel.rows.isEmpty)

        try store.saveTrainingSessions([session])
        notificationCenter.post(name: .trainingSessionsDidChange, object: nil)

        await fulfillment(of: [rowsRefreshed], timeout: 1)
        XCTAssertEqual(viewModel.rows, [
            TrainingSessionRowViewData(
                id: session.id,
                startedAt: session.startedAt,
                titleDate: session.events[0].markedAt,
                descriptionStartedAt: session.events[0].markedAt,
                descriptionEndedAt: session.events[0].markedAt,
                markerCount: 1,
            ),
        ])
    }

    private func makeSession(
        id: String,
        startedAt: Date = Date(timeIntervalSince1970: 2000),
    ) throws -> TrainingSession {
        try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: id)),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            events: [
                ShotMarkerEvent(
                    id: UUID(),
                    markedAt: startedAt.addingTimeInterval(300),
                ),
            ],
        )
    }
}

private enum TrainingSessionListStoreError: Error {
    case failed
}

private struct SpyLogEntry {
    let level: AppLogLevel
    let category: AppLogCategory
    let name: String
    let message: String
    let context: [String: String]
    let errorDescription: String?
}

private final class SpyAppLogger: AppLogging {
    private(set) var entries: [SpyLogEntry] = []

    func debug(_ name: String, category: AppLogCategory, message: String, context: [String: String]) {
        append(level: .debug, category: category, name: name, message: message, context: context)
    }

    func info(_ name: String, category: AppLogCategory, message: String, context: [String: String]) {
        append(level: .info, category: category, name: name, message: message, context: context)
    }

    func warning(_ name: String, category: AppLogCategory, message: String, context: [String: String]) {
        append(level: .warning, category: category, name: name, message: message, context: context)
    }

    func error(
        _ name: String,
        category: AppLogCategory,
        message: String,
        error: Error?,
        context: [String: String],
    ) {
        append(
            level: .error,
            category: category,
            name: name,
            message: message,
            context: context,
            errorDescription: error.map { String(describing: $0) },
        )
    }

    func entry(named name: String) -> SpyLogEntry? {
        entries.first { $0.name == name }
    }

    private func append(
        level: AppLogLevel,
        category: AppLogCategory,
        name: String,
        message: String,
        context: [String: String],
        errorDescription: String? = nil,
    ) {
        entries.append(
            SpyLogEntry(
                level: level,
                category: category,
                name: name,
                message: message,
                context: context,
                errorDescription: errorDescription,
            ),
        )
    }
}

private final class ThrowingTrainingSessionStore: TrainingSessionStoreProtocol {
    private var sessions: [TrainingSession]
    private let loadError: Error?
    private let saveError: Error?

    init(
        sessions: [TrainingSession] = [],
        loadError: Error? = nil,
        saveError: Error? = nil,
    ) {
        self.sessions = sessions
        self.loadError = loadError
        self.saveError = saveError
    }

    func loadTrainingSessions() throws -> [TrainingSession] {
        if let loadError {
            throw loadError
        }

        return sessions
    }

    func saveTrainingSessions(_ sessions: [TrainingSession]) throws {
        if let saveError {
            throw saveError
        }

        self.sessions = sessions
    }
}

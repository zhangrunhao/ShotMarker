@testable import ShotMarker
import Combine
import XCTest

final class TrainingSessionListViewModelTests: XCTestCase {
    func testLoadSortsTrainingSessionsNewestFirst() throws {
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
        let viewModel = TrainingSessionListViewModel(store: InMemoryTrainingSessionStore(sessions: [older, newer]))

        viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.id), [newer.id, older.id])
    }

    func testLoadMapsTrainingSessionStateIntoRows() throws {
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
        let viewModel = TrainingSessionListViewModel(store: InMemoryTrainingSessionStore(sessions: [session]))

        viewModel.load()

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

    func testSessionReturnsLoadedSessionForRowID() throws {
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000005")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2300),
            events: [],
        )
        let viewModel = TrainingSessionListViewModel(store: InMemoryTrainingSessionStore(sessions: [session]))

        viewModel.load()

        XCTAssertEqual(viewModel.session(for: session.id), session)
    }

    func testLoadMapsRowTitleDateAndDescriptionRangeFromEarliestAndLatestMarkers() throws {
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
        let viewModel = TrainingSessionListViewModel(store: InMemoryTrainingSessionStore(sessions: [session]))

        viewModel.load()

        XCTAssertEqual(viewModel.rows.first?.titleDate, firstMarker.markedAt)
        XCTAssertEqual(viewModel.rows.first?.descriptionStartedAt, firstMarker.markedAt)
        XCTAssertEqual(viewModel.rows.first?.descriptionEndedAt, lastMarker.markedAt)
    }

    func testLoadFallsBackToSessionRangeWhenRowHasNoMarkers() throws {
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000204")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2800),
            events: [],
        )
        let viewModel = TrainingSessionListViewModel(store: InMemoryTrainingSessionStore(sessions: [session]))

        viewModel.load()

        XCTAssertEqual(viewModel.rows.first?.titleDate, session.startedAt)
        XCTAssertEqual(viewModel.rows.first?.descriptionStartedAt, session.startedAt)
        XCTAssertEqual(viewModel.rows.first?.descriptionEndedAt, session.endedAt)
    }

    func testMergeSelectedSessionsCombinesSelectedRowsIntoOneSession() throws {
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
        let viewModel = TrainingSessionListViewModel(store: store)

        viewModel.load()
        viewModel.beginSelection(with: firstSession.id)
        viewModel.toggleSelection(for: secondSession.id)
        viewModel.mergeSelectedSessions()

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

    func testMergeRequiresAtLeastTwoSelectedSessions() throws {
        let session = try TrainingSession(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000401")),
            startedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2600),
            events: [],
        )
        let store = InMemoryTrainingSessionStore(sessions: [session])
        let viewModel = TrainingSessionListViewModel(store: store)

        viewModel.load()
        viewModel.beginSelection(with: session.id)
        viewModel.mergeSelectedSessions()

        XCTAssertEqual(try store.loadTrainingSessions(), [session])
        XCTAssertTrue(viewModel.isSelectionMode)
        XCTAssertFalse(viewModel.canMergeSelectedSessions)
    }

    func testLoadShowsEmptyStateWhenNoTrainingSessionsExist() {
        let viewModel = TrainingSessionListViewModel(store: InMemoryTrainingSessionStore(sessions: []))

        viewModel.load()

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testRowsRefreshWhenTrainingSessionsDidChangeNotificationIsPosted() throws {
        let store = InMemoryTrainingSessionStore(sessions: [])
        let notificationCenter = NotificationCenter()
        let viewModel = TrainingSessionListViewModel(
            store: store,
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
                if rows.map({ $0.id }) == [session.id] {
                    rowsRefreshed.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.load()
        XCTAssertTrue(viewModel.rows.isEmpty)

        try store.saveTrainingSessions([session])
        notificationCenter.post(name: .trainingSessionsDidChange, object: nil)

        wait(for: [rowsRefreshed], timeout: 1)
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
}

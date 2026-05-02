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
                markerCount: 1,
            ),
        ])
        XCTAssertFalse(viewModel.isEmpty)
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
                markerCount: 1,
            ),
        ])
    }
}

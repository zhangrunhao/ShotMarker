@testable import ShotMarker
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
}

import XCTest
@testable import ShotMarker

final class TrainingSessionListViewModelTests: XCTestCase {
    func testLoadSortsTrainingSessionsNewestFirst() {
        let older = TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            trainingDate: Date(timeIntervalSince1970: 1_000),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_300),
            events: [],
            syncStatus: .synced,
            highlightStatus: .notClipped
        )
        let newer = TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            trainingDate: Date(timeIntervalSince1970: 2_000),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 2_300),
            events: [],
            syncStatus: .synced,
            highlightStatus: .notClipped
        )
        let viewModel = TrainingSessionListViewModel(store: InMemoryTrainingSessionStore(sessions: [older, newer]))

        viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.id), [newer.id, older.id])
    }

    func testLoadMapsTrainingSessionStateIntoRows() {
        let marker = ShotMarkerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            markedAt: Date(timeIntervalSince1970: 2_100),
            source: .watch
        )
        let session = TrainingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            trainingDate: Date(timeIntervalSince1970: 2_000),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 2_300),
            events: [marker],
            syncStatus: .pending,
            highlightStatus: .clipped
        )
        let viewModel = TrainingSessionListViewModel(store: InMemoryTrainingSessionStore(sessions: [session]))

        viewModel.load()

        XCTAssertEqual(viewModel.rows, [
            TrainingSessionRowViewData(
                id: session.id,
                trainingDate: session.trainingDate,
                startedAt: session.startedAt,
                markerCount: 1,
                syncStatus: .pending,
                highlightStatus: .clipped
            )
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

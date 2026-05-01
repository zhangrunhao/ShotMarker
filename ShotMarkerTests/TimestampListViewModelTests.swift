import XCTest
@testable import ShotMarker

final class TimestampListViewModelTests: XCTestCase {
    func testLoadSortsTimestampFilesNewestFirst() {
        let older = TimestampFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            trainingDate: Date(timeIntervalSince1970: 1_000),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_300),
            events: [],
            syncStatus: .synced,
            highlightStatus: .notClipped
        )
        let newer = TimestampFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            trainingDate: Date(timeIntervalSince1970: 2_000),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 2_300),
            events: [],
            syncStatus: .synced,
            highlightStatus: .notClipped
        )
        let viewModel = TimestampListViewModel(store: InMemoryTimestampFileStore(files: [older, newer]))

        viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.id), [newer.id, older.id])
    }

    func testLoadMapsTimestampFileStateIntoRows() {
        let marker = ShotMarkerEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            markedAt: Date(timeIntervalSince1970: 2_100),
            source: .watch
        )
        let file = TimestampFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            trainingDate: Date(timeIntervalSince1970: 2_000),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 2_300),
            events: [marker],
            syncStatus: .pending,
            highlightStatus: .clipped
        )
        let viewModel = TimestampListViewModel(store: InMemoryTimestampFileStore(files: [file]))

        viewModel.load()

        XCTAssertEqual(viewModel.rows, [
            TimestampFileRowViewData(
                id: file.id,
                trainingDate: file.trainingDate,
                startedAt: file.startedAt,
                markerCount: 1,
                syncStatus: .pending,
                highlightStatus: .clipped
            )
        ])
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testLoadShowsEmptyStateWhenNoTimestampFilesExist() {
        let viewModel = TimestampListViewModel(store: InMemoryTimestampFileStore(files: []))

        viewModel.load()

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertTrue(viewModel.isEmpty)
    }
}

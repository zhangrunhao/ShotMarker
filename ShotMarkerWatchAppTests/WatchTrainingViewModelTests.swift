@testable import ShotMarkerWatchApp
import SwiftUI
import XCTest

final class WatchTrainingViewModelTests: XCTestCase {
    func testInitialStateIsNotTraining() {
        let viewModel = WatchTrainingViewModel()

        XCTAssertEqual(viewModel.state, .notTraining)
        XCTAssertEqual(viewModel.buttonTitle, "长按开始")
        XCTAssertEqual(viewModel.buttonColor, .green)
        XCTAssertEqual(viewModel.markerCount, 0)
        XCTAssertEqual(viewModel.markerCountText, "打点数: 0")
    }

    func testLongPressStartsTrainingFromNotTrainingState() {
        let viewModel = WatchTrainingViewModel(now: { Date(timeIntervalSince1970: 1000) })

        let payload = viewModel.handleLongPress()

        XCTAssertNil(payload)
        XCTAssertEqual(viewModel.state, .training)
        XCTAssertEqual(viewModel.startedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(viewModel.buttonTitle, "双击打点 / 长按结束")
        XCTAssertEqual(viewModel.buttonColor, .red)
        XCTAssertEqual(viewModel.markerCountText, "打点数: 0")
    }

    func testLongPressEndsTrainingFromTrainingState() throws {
        var dates = [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 1120),
            Date(timeIntervalSince1970: 1600),
        ]
        let sessionId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000301"))
        let eventId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000302"))
        var ids = [
            sessionId,
            eventId,
        ]
        let viewModel = WatchTrainingViewModel(
            now: { dates.removeFirst() },
            idFactory: { ids.removeFirst() },
        )

        viewModel.handleLongPress()
        viewModel.handleDoubleTap()
        let payload = viewModel.handleLongPress()

        XCTAssertEqual(viewModel.state, .notTraining)
        XCTAssertEqual(viewModel.endedAt, Date(timeIntervalSince1970: 1600))
        XCTAssertEqual(viewModel.buttonTitle, "长按开始")
        XCTAssertEqual(viewModel.buttonColor, .green)
        XCTAssertEqual(viewModel.markerCount, 0)
        XCTAssertEqual(viewModel.markerCountText, "打点数: 0")
        XCTAssertEqual(
            payload,
            TrainingSessionSyncPayload(
                id: sessionId,
                startedAt: Date(timeIntervalSince1970: 1000),
                endedAt: Date(timeIntervalSince1970: 1600),
                events: [
                    ShotMarkerEventSyncPayload(
                        id: eventId,
                        markedAt: Date(timeIntervalSince1970: 1120),
                    ),
                ],
            ),
        )
    }

    func testDoubleTapDoesNothingWhenNotTraining() {
        let viewModel = WatchTrainingViewModel(now: { Date(timeIntervalSince1970: 2000) })

        let didRecord = viewModel.handleDoubleTap()

        XCTAssertFalse(didRecord)
        XCTAssertEqual(viewModel.markers, [])
    }

    func testDoubleTapRecordsMarkerWhenStarted() {
        var dates = [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 1120),
        ]
        let viewModel = WatchTrainingViewModel(now: { dates.removeFirst() })

        viewModel.handleLongPress()
        let didRecord = viewModel.handleDoubleTap()

        XCTAssertTrue(didRecord)
        XCTAssertEqual(viewModel.markers, [Date(timeIntervalSince1970: 1120)])
        XCTAssertEqual(viewModel.markerCount, 1)
        XCTAssertEqual(viewModel.markerCountText, "打点数: 1")
    }
}

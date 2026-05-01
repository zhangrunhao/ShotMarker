import XCTest
@testable import ShotMarkerWatchApp

final class WatchTrainingViewModelTests: XCTestCase {
    func testInitialStateIsEnded() {
        let viewModel = WatchTrainingViewModel()

        XCTAssertEqual(viewModel.state, .ended)
        XCTAssertEqual(viewModel.buttonTitle, "开始")
        XCTAssertEqual(viewModel.markerCount, 0)
    }

    func testLongPressStartsTrainingFromEndedState() {
        let viewModel = WatchTrainingViewModel(now: { Date(timeIntervalSince1970: 1_000) })

        viewModel.handleLongPress()

        XCTAssertEqual(viewModel.state, .started)
        XCTAssertEqual(viewModel.startedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(viewModel.buttonTitle, "结束")
    }

    func testLongPressEndsTrainingFromStartedState() {
        var dates = [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 1_600)
        ]
        let viewModel = WatchTrainingViewModel(now: { dates.removeFirst() })

        viewModel.handleLongPress()
        viewModel.handleLongPress()

        XCTAssertEqual(viewModel.state, .ended)
        XCTAssertEqual(viewModel.endedAt, Date(timeIntervalSince1970: 1_600))
    }
}
